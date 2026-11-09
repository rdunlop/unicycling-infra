# Example of how unicycling-registration calls the modules. Used to validate the modules in CI.
# Do not apply this example. Real environments live in the app repos, pinned to a module tag.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

module "alb" {
  source = "../../modules/alb-ingress"

  app_name              = "unicycling-registration"
  environment           = var.environment
  vpc_id                = var.vpc_id
  subnet_ids            = var.subnet_ids
  zone_id               = var.zone_id
  domain                = var.domain
  alb_domain            = var.alb_domain
  subject_alt_names     = var.subject_alt_names
  wildcard_domain       = var.wildcard_domain
  ec2_instance_id       = var.ec2_instance_id
  ec2_security_group_id = var.ec2_security_group_id
  ecs_target_group_name = "unicycling-reg-${var.environment}-ecs"
  ecs_traffic_weight    = var.ecs_traffic_weight
}

module "ecs_app" {
  source = "../../modules/ecs-app"

  app_name                   = "unicycling-registration"
  environment                = var.environment
  vpc_id                     = var.vpc_id
  subnet_ids                 = var.subnet_ids
  alb_security_group_id      = module.alb.alb_security_group_id
  target_group_arn           = module.alb.target_group_arn
  database_security_group_id = var.rds_security_group_id
  redis_security_group_id    = var.elasticache_security_group_id
  ecr_repository_url         = var.ecr_repository_url
  image_tag                  = var.image_tag

  web_cpu        = var.environment == "staging" ? 1024 : 2048
  web_memory     = var.environment == "staging" ? 2048 : 4096
  sidekiq_cpu    = var.environment == "staging" ? 512 : 1024
  sidekiq_memory = var.environment == "staging" ? 1024 : 2048

  environment_vars = [
    { name = "RAILS_ENV", value = var.rails_env },
    { name = "PORT", value = "3000" },
    { name = "RAILS_LOG_TO_STDOUT", value = "1" },
    { name = "RAILS_SERVE_STATIC_FILES", value = "true" },
    { name = "RAILS_MAX_THREADS", value = "5" },
    { name = "DOMAIN", value = var.domain },
    { name = "SSL_ENABLED", value = "false" },
    { name = "ROBOTS_DISALLOW_ALL", value = var.environment == "staging" ? "true" : "false" },
  ]

  web_environment_extra = [
    { name = "REDIS_CACHE_URL", value = "redis://127.0.0.1:6379/1" },
  ]

  sidecars = [
    {
      name    = "redis-cache"
      image   = "redis:7-alpine"
      cpu     = 128
      memory  = 256
      command = ["redis-server", "--bind", "127.0.0.1", "--maxmemory", "128mb", "--maxmemory-policy", "allkeys-lru"]
    },
  ]

  secret_names = [
    "SECRET_KEY_BASE",
    "DATABASE_HOST", "POSTGRES_USER", "POSTGRES_PASSWORD", "POSTGRES_DB",
    "REDIS_URL",
    "AWS_REGION", "AWS_BUCKET", "AWS_ACCESS_KEY", "AWS_SECRET_ACCESS_KEY",
  ]

  container_insights = var.environment == "staging" ? "disabled" : "enabled"

  task_policy_statements = [
    {
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = "*"
    },
    {
      Effect   = "Allow"
      Action   = ["ses:SendRawEmail", "ses:SendEmail"]
      Resource = "*"
    },
  ]

  scheduled_tasks = [
    {
      name                = "update-registration-period"
      description         = "Daily rake update_registration_period (replaces whenever cron)"
      schedule_expression = "cron(0 0 * * ? *)"
      command             = ["bundle", "exec", "rake", "update_registration_period"]
    },
  ]
}
