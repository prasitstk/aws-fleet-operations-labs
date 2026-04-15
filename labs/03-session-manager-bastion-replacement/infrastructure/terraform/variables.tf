variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "session-manager"
}

variable "environment" {
  description = "Environment name (dev, staging, prod). Used in parameter hierarchy path."
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
  description = "EC2 instance type for the session target instance."
  type        = string
  default     = "t2.micro"
}

variable "notification_email" {
  description = "Email address for SNS session notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "session_log_bucket_prefix" {
  description = "Custom S3 bucket name for session logs. Leave empty for auto-generated name."
  type        = string
  default     = ""
}

variable "session_log_expiration_days" {
  description = "Number of days before session log objects expire in S3."
  type        = number
  default     = 90
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain session logs in CloudWatch Logs."
  type        = number
  default     = 30
}

variable "idle_session_timeout" {
  description = "Idle session timeout in minutes."
  type        = number
  default     = 20
}

variable "max_session_duration" {
  description = "Maximum session duration in minutes."
  type        = number
  default     = 60
}

variable "run_as_enabled" {
  description = "Enable Run As for Session Manager sessions."
  type        = bool
  default     = false
}

variable "run_as_default_user" {
  description = "Default OS user for Run As sessions."
  type        = string
  default     = "ssm-user"
}

variable "shell_profile_commands" {
  description = "Shell profile commands executed when a session starts."
  type        = string
  default     = "cd ~ && exec bash"
}

variable "db_password" {
  description = "Demo database password stored as SecureString parameter (encrypted with KMS)."
  type        = string
  sensitive   = true
  default     = "s3cur3-dem0-p@ssw0rd"
}
