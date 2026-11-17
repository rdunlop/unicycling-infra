variable "app_name" {
  type        = string
  description = "Application name, e.g. unicycling-registration. The ALB and EC2 target group are named <app_name>-<environment>."
}

variable "environment" {
  type        = string
  description = "Environment name, e.g. staging or prod."
}

variable "vpc_id" {
  type        = string
  description = "VPC for the ALB and target groups."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Public subnets for the ALB. Give at least 2, in different AZs. Fewer AZs means fewer billed public IPs."
}

variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID for the domains below."
}

variable "domain" {
  type        = string
  description = "Domain for the ACM certificate. Created as a CNAME to alb_domain."
}

variable "alb_domain" {
  type        = string
  description = "Domain the ALB actually serves. Gets an A (alias) record to the ALB."
}

variable "subject_alt_names" {
  type        = list(string)
  description = "Extra SANs for the ACM certificate."
  default     = []
}

variable "wildcard_domain" {
  type        = string
  description = "Optional wildcard domain (e.g. *.regtest.example.com) CNAMEd to alb_domain, so tenant subdomains reach the ALB."
  default     = null
}

variable "legacy_ec2" {
  type = object({
    instance_id       = string
    security_group_id = string
  })
  description = "Optional. Set while a legacy EC2 app is still serving traffic during cutover: creates an EC2 target group with that instance, and appends an ALB ingress rule to its security group. Leave null once EC2 is gone; the module then creates no EC2 resources and forwards all traffic to ECS."
  default     = null
}

variable "ecs_target_group_name" {
  type        = string
  description = "Name of the ECS (ip) target group. Max 32 characters, so it is passed in explicitly."
}

variable "ecs_port" {
  type        = number
  description = "Port the ECS web tasks listen on. Must match the app's web_port."
  default     = 3000
}

variable "ecs_health_check_path" {
  type        = string
  description = "Path the ECS target group health check requests. Must return 200-399 without credentials. Defaults to \"/\", which returns a 302 for unauthenticated users; set a dedicated path such as /healthcheck to keep health checks out of app logs and to allow HTTP basic auth on the rest of the site."
  default     = "/"
}

variable "ecs_traffic_weight" {
  type        = number
  description = "Percentage of HTTPS traffic sent to ECS (0-100) while legacy_ec2 is set. The EC2 target group gets the remainder. Ignored when legacy_ec2 is null."
  default     = 0

  validation {
    condition     = var.ecs_traffic_weight >= 0 && var.ecs_traffic_weight <= 100
    error_message = "ecs_traffic_weight must be between 0 and 100."
  }
}
