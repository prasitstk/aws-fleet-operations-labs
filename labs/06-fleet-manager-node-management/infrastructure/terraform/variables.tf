variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "fleet-manager"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for fleet nodes."
  type        = string
  default     = "t2.micro"
}

variable "instance_count" {
  description = "Number of fleet instances to launch."
  type        = number
  default     = 2
}

variable "app_port" {
  description = "HTTP port for the financial collector application."
  type        = number
  default     = 8080
}

variable "notification_email" {
  description = "Email address for SNS Run Command notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "cw_agent_collection_interval" {
  description = "CloudWatch Agent metrics collection interval in seconds."
  type        = number
  default     = 60
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain collector logs in CloudWatch Logs."
  type        = number
  default     = 30
}
