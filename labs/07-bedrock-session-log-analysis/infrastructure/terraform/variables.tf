variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "bedrock-session-log-analysis"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type (t3.micro for Bedrock lab)"
}

variable "notification_email" {
  type        = string
  default     = ""
  description = "Email for SNS analysis notifications (leave empty to skip subscription)"
}

variable "session_log_bucket_prefix" {
  type        = string
  default     = ""
  description = "Custom S3 bucket name for session logs (auto-generated if empty)"
}

variable "session_log_expiration_days" {
  type    = number
  default = 90
}

variable "cloudwatch_log_retention_days" {
  type    = number
  default = 30
}

variable "bedrock_model_id" {
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
  description = "Bedrock cross-region inference profile ID for session log analysis"
}

variable "lambda_timeout" {
  type        = number
  default     = 150
  description = "Lambda timeout in seconds (120s CloudTrail wait + 30s buffer for Bedrock)"
}

variable "lambda_memory_size" {
  type        = number
  default     = 256
  description = "Lambda memory in MB"
}

variable "create_session_document" {
  type        = bool
  default     = true
  description = "Create SSM-SessionManagerRunShell document. Set false if Lab 03 is deployed (account-level singleton per region)."
}
