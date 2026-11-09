# Public ALB, ACM certificate, and DNS for an ECS app. Also keeps the legacy EC2 target group
# so traffic can be split during cutover (ecs_traffic_weight).
#
# Extracted from unicycling-registration/terraform (security_groups.tf, alb.tf, acm.tf, dns.tf).

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-${var.environment}-alb"
  description = "ALB security group for ${var.environment}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}-alb"
    Environment = var.environment
  }
}

# Appends an ingress rule to the existing EC2 security group. Does not replace the group.
resource "aws_security_group_rule" "ec2_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = var.ec2_security_group_id
  source_security_group_id = aws_security_group.alb.id
  description              = "Allow HTTP from ${var.environment} ALB"
}

resource "aws_lb" "app" {
  name               = "${var.app_name}-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  tags = {
    Name        = "${var.app_name}-${var.environment}"
    Environment = var.environment
  }
}

# Legacy EC2 target group.
resource "aws_lb_target_group" "app" {
  name     = "${var.app_name}-${var.environment}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    # "/" returns 302 for unauthenticated users; 200-399 accepts redirects.
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = var.ec2_instance_id
  port             = 80
}

# ECS target group (ip type, required for Fargate awsvpc networking).
resource "aws_lb_target_group" "ecs" {
  name        = var.ecs_target_group_name
  port        = var.ecs_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200-399"
  }

  tags = {
    Name        = var.ecs_target_group_name
    Environment = var.environment
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app.certificate_arn

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.app.arn
        weight = 100 - var.ecs_traffic_weight
      }
      target_group {
        arn    = aws_lb_target_group.ecs.arn
        weight = var.ecs_traffic_weight
      }
    }
  }
}

# ---- ACM ----

resource "aws_acm_certificate" "app" {
  domain_name               = var.domain
  subject_alternative_names = var.subject_alt_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.app_name}-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# ---- DNS ----

resource "aws_route53_record" "app" {
  zone_id         = var.zone_id
  name            = var.domain
  type            = "CNAME"
  ttl             = 300
  records         = [var.alb_domain]
  allow_overwrite = true
}

resource "aws_route53_record" "alb" {
  zone_id         = var.zone_id
  name            = var.alb_domain
  type            = "A"
  allow_overwrite = true

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "wildcard" {
  count           = var.wildcard_domain != null ? 1 : 0
  zone_id         = var.zone_id
  name            = var.wildcard_domain
  type            = "CNAME"
  ttl             = 300
  records         = [var.alb_domain]
  allow_overwrite = true
}
