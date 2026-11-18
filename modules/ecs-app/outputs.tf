output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.app.name
}

output "cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.app.arn
}

output "web_service_name" {
  description = "ECS web service name"
  value       = aws_ecs_service.web.name
}

output "sidekiq_service_name" {
  description = "ECS sidekiq service name. Null when sidekiq_enabled is false."
  value       = var.sidekiq_enabled ? aws_ecs_service.sidekiq[0].name : null
}

output "ecs_tasks_security_group_id" {
  description = "Security group attached to the Fargate tasks"
  value       = aws_security_group.ecs_tasks.id
}

output "web_task_definition_family" {
  description = "Family of the web task definition (scheduled tasks and CI use this)"
  value       = aws_ecs_task_definition.web.family
}
