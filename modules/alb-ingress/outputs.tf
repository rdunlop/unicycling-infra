output "alb_security_group_id" {
  description = "Security group of the ALB. Pass to ecs-app as alb_security_group_id."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "ARN of the ECS (ip) target group. Pass to ecs-app as target_group_arn."
  value       = aws_lb_target_group.ecs.arn
}

output "ec2_target_group_arn" {
  description = "ARN of the legacy EC2 target group, or null when legacy_ec2 is not set"
  value       = one(aws_lb_target_group.legacy_ec2[*].arn)
}

output "alb_dns_name" {
  description = "ALB DNS name, for smoke tests before DNS cutover"
  value       = aws_lb.app.dns_name
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "acm_certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate_validation.app.certificate_arn
}
