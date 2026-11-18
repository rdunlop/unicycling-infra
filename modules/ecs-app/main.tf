# ECS Fargate application: cluster, web + sidekiq task definitions and services,
# IAM roles, security groups, log groups, and scheduled tasks.
#
# Extracted from unicycling-registration/terraform with app-specific values turned into inputs.
# Resource names and settings match the original so that moving a project onto this module is a
# refactor with no changes, which the project's plan has to confirm.

data "aws_caller_identity" "current" {}

locals {
  name       = "${var.app_name}-${var.environment}"
  ssm_prefix = "/${var.app_name}/${var.environment}"
  account_id = data.aws_caller_identity.current.account_id
  image      = "${var.ecr_repository_url}:${var.image_tag}"

  secrets = [
    for name in var.secret_names : {
      name      = name
      valueFrom = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}/${name}"
    }
  ]

  web_environment     = concat(var.environment_vars, var.web_environment_extra)
  sidekiq_environment = concat(var.environment_vars, var.sidekiq_environment_extra)
}

# ---- Cluster and logs ----

resource "aws_ecs_cluster" "app" {
  name = local.name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  tags = {
    Name        = local.name
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name}-web"
  retention_in_days = var.log_retention_days
  tags              = { Environment = var.environment }
}

resource "aws_cloudwatch_log_group" "sidekiq" {
  name              = "/ecs/${local.name}-sidekiq"
  retention_in_days = var.log_retention_days
  tags              = { Environment = var.environment }
}

# ---- Security groups ----

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name}-ecs-tasks"
  description = "ECS Fargate tasks for ${var.environment}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB"
    from_port       = var.web_port
    to_port         = var.web_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${local.name}-ecs-tasks"
    Environment = var.environment
  }
}

resource "aws_security_group_rule" "database_from_ecs" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = var.database_security_group_id
  source_security_group_id = aws_security_group.ecs_tasks.id
  description              = "PostgreSQL from ECS tasks (${var.environment})"
}

# Only for apps that use the shared ElastiCache cluster (redis_security_group_id set).
# Apps without Redis pass null and get no rule.
resource "aws_security_group_rule" "redis_from_ecs" {
  count                    = var.redis_security_group_id == null ? 0 : 1
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = var.redis_security_group_id
  source_security_group_id = aws_security_group.ecs_tasks.id
  description              = "Redis from ECS tasks (${var.environment})"
}

# Callers that already had this rule (registration, rulebook) keep their state address.
moved {
  from = aws_security_group_rule.redis_from_ecs
  to   = aws_security_group_rule.redis_from_ecs[0]
}

# ---- IAM ----

# Execution role: used by the ECS agent to pull images, read SSM secrets, and write logs.
resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "ssm-read"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.region}:${local.account_id}:parameter${local.ssm_prefix}/*"
    }]
  })
}

# Task role: assumed by the app for AWS API calls.
resource "aws_iam_role" "ecs_task" {
  name = "${local.name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_permissions" {
  name = "app-permissions"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(var.task_policy_statements, [
      {
        # Required for ECS Exec (interactive debugging).
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        Resource = "*"
      },
    ])
  })
}

# ---- Task definitions ----

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode(concat(
    [
      merge(
        {
          name            = "web"
          image           = local.image
          essential       = true
          portMappings    = [{ containerPort = var.web_port, hostPort = var.web_port, protocol = "tcp" }]
          linuxParameters = { initProcessEnabled = true }
          environment     = local.web_environment
          secrets         = local.secrets
          mountPoints     = []
          systemControls  = []
          volumesFrom     = []
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.web.name
              "awslogs-region"        = var.region
              "awslogs-stream-prefix" = "web"
            }
          }
        },
        length(var.sidecars) > 0 ? {
          dependsOn = [for s in var.sidecars : { containerName = s.name, condition = "START" }]
        } : {},
      )
    ],
    [
      for s in var.sidecars : merge(
        {
          name           = s.name
          image          = s.image
          essential      = false
          environment    = []
          mountPoints    = []
          portMappings   = []
          systemControls = []
          volumesFrom    = []
          cpu            = s.cpu
          memory         = s.memory
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.web.name
              "awslogs-region"        = var.region
              "awslogs-stream-prefix" = s.name
            }
          }
        },
        s.command != null ? { command = s.command } : {},
      )
    ],
  ))

  tags = { Environment = var.environment }
}

resource "aws_ecs_task_definition" "sidekiq" {
  family                   = "${local.name}-sidekiq"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.sidekiq_cpu
  memory                   = var.sidekiq_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name            = "sidekiq"
      image           = local.image
      essential       = true
      command         = var.sidekiq_command
      linuxParameters = { initProcessEnabled = true }
      environment     = local.sidekiq_environment
      secrets         = local.secrets
      mountPoints     = []
      portMappings    = []
      systemControls  = []
      volumesFrom     = []
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.sidekiq.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "sidekiq"
        }
      }
    },
  ])

  tags = { Environment = var.environment }
}

# ---- Services ----
# desired_count starts at 0; scale up once SSM secrets exist.
# task_definition is ignored so deploys that register new revisions outside Terraform do not
# show as drift. This is what the next phase changes.

resource "aws_ecs_service" "web" {
  name                   = "${local.name}-web"
  cluster                = aws_ecs_cluster.app.id
  task_definition        = aws_ecs_task_definition.web.arn
  desired_count          = 0
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "web"
    container_port   = var.web_port
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Environment = var.environment }
}

resource "aws_ecs_service" "sidekiq" {
  name                   = "${local.name}-sidekiq"
  cluster                = aws_ecs_cluster.app.id
  task_definition        = aws_ecs_task_definition.sidekiq.arn
  desired_count          = 0
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = { Environment = var.environment }
}

# ---- Scheduled tasks (replaces whenever/cron) ----

resource "aws_iam_role" "eventbridge_ecs" {
  count = length(var.scheduled_tasks) > 0 ? 1 : 0
  name  = "${local.name}-eventbridge-ecs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_ecs" {
  count = length(var.scheduled_tasks) > 0 ? 1 : 0
  name  = "run-ecs-task"
  role  = aws_iam_role.eventbridge_ecs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "arn:aws:ecs:${var.region}:${local.account_id}:task-definition/${aws_ecs_task_definition.web.family}:*"
        Condition = {
          ArnLike = { "ecs:cluster" = aws_ecs_cluster.app.arn }
        }
      },
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn,
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "scheduled" {
  for_each = { for t in var.scheduled_tasks : t.name => t }

  name                = "${local.name}-${each.value.name}"
  description         = each.value.description
  schedule_expression = each.value.schedule_expression
}

resource "aws_cloudwatch_event_target" "scheduled" {
  for_each = { for t in var.scheduled_tasks : t.name => t }

  rule     = aws_cloudwatch_event_rule.scheduled[each.key].name
  arn      = aws_ecs_cluster.app.arn
  role_arn = aws_iam_role.eventbridge_ecs[0].arn

  ecs_target {
    # No revision number: EventBridge uses the latest active revision of the family.
    task_definition_arn = "arn:aws:ecs:${var.region}:${local.account_id}:task-definition/${aws_ecs_task_definition.web.family}"
    task_count          = 1
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [aws_security_group.ecs_tasks.id]
      assign_public_ip = true
    }
  }

  input = jsonencode({
    containerOverrides = [{
      name    = "web"
      command = each.value.command
    }]
  })
}
