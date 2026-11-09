variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "zone_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "alb_domain" {
  type = string
}

variable "subject_alt_names" {
  type    = list(string)
  default = []
}

variable "wildcard_domain" {
  type    = string
  default = null
}

variable "ec2_instance_id" {
  type = string
}

variable "ec2_security_group_id" {
  type = string
}

variable "ecs_traffic_weight" {
  type    = number
  default = 100
}

variable "rds_security_group_id" {
  type = string
}

variable "elasticache_security_group_id" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "image_tag" {
  type = string
}

variable "rails_env" {
  type = string
}
