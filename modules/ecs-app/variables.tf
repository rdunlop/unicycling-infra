variable "app_name" {
  type        = string
  description = "Application name used for every resource name and SSM prefix, e.g. unicycling-registration"
}

variable "environment" {
  type        = string
  description = "Environment name, e.g. staging or prod. Appears in resource names."
}

variable "region" {
  type        = string
  description = "AWS region for the ECS resources. Used in ARNs and awslogs options."
  default     = "us-west-2"
}

variable "vpc_id" {
  type        = string
  description = "VPC that holds the ECS tasks."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for Fargate tasks. Must be the same subnets the ALB serves, so tasks are reachable."
}

variable "alb_security_group_id" {
  type        = string
  description = "Security group of the ALB. Tasks accept web_port traffic from it only."
}

variable "target_group_arn" {
  type        = string
  description = "ARN of the ALB target group (ip type) that the web service registers with."
}

variable "database_security_group_id" {
  type        = string
  description = "Security group of the shared RDS instance. Gets a port 5432 ingress rule from the tasks."
}

variable "redis_security_group_id" {
  type        = string
  description = "Security group of the shared ElastiCache cluster. Gets a port 6379 ingress rule from the tasks."
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL without a tag."
}

variable "image_tag" {
  type        = string
  description = "Image tag to deploy. The caller should supply this (bin/tf does, from the live ECS image)."
}

variable "web_port" {
  type        = number
  description = "Port the web container listens on."
  default     = 3000
}

variable "web_cpu" {
  type        = number
  description = "Fargate CPU units for the web task."
}

variable "web_memory" {
  type        = number
  description = "Fargate memory (MiB) for the web task."
}

variable "sidekiq_cpu" {
  type        = number
  description = "Fargate CPU units for the sidekiq task."
}

variable "sidekiq_memory" {
  type        = number
  description = "Fargate memory (MiB) for the sidekiq task."
}

variable "sidekiq_command" {
  type        = list(string)
  description = "Command for the sidekiq container."
  default     = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
}

variable "environment_vars" {
  type        = list(object({ name = string, value = string }))
  description = "Plain environment variables for both the web and sidekiq containers."
}

variable "web_environment_extra" {
  type        = list(object({ name = string, value = string }))
  description = "Extra environment variables for the web container only."
  default     = []
}

variable "sidekiq_environment_extra" {
  type        = list(object({ name = string, value = string }))
  description = "Extra environment variables for the sidekiq container only."
  default     = []
}

variable "secret_names" {
  type        = list(string)
  description = "Names of SSM SecureString parameters under /<app_name>/<environment>/ injected as container secrets into both containers."
  default     = []
}

variable "sidecars" {
  type = list(object({
    name    = string
    image   = string
    cpu     = number
    memory  = number
    command = optional(list(string))
  }))
  description = "Sidecar containers added to the web task only (not essential, so they can restart without stopping web)."
  default     = []
}

variable "container_insights" {
  type        = string
  description = "ECS cluster Container Insights setting: enabled, enhanced or disabled."
  default     = "enabled"

  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights must be enabled, enhanced or disabled."
  }
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch log retention for the web and sidekiq log groups."
  default     = 30
}

variable "task_policy_statements" {
  type        = list(any)
  description = "IAM policy statements for the task role (what the app itself may call). ECS Exec permissions are added by the module."
  default     = []
}

variable "scheduled_tasks" {
  type = list(object({
    name                = string
    description         = string
    schedule_expression = string
    command             = list(string)
  }))
  description = "One-off ECS tasks run on an EventBridge schedule, using the latest web task definition. Each command runs in the web container."
  default     = []
}
