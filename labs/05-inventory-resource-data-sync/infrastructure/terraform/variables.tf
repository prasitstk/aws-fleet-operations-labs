variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "ssm-inventory-lab"
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

variable "linux_instance_type" {
  description = "EC2 instance type for the Linux inventory target."
  type        = string
  default     = "t2.micro"
}

variable "windows_instance_type" {
  description = "EC2 instance type for the Windows inventory target."
  type        = string
  default     = "t3.micro"
}

variable "linux_ami_name_filter" {
  description = "AMI name filter for Amazon Linux 2023."
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "windows_ami_name_filter" {
  description = "AMI name filter for Windows Server 2025."
  type        = string
  default     = "Windows_Server-2025-English-Full-Base-*"
}

variable "inventory_schedule" {
  description = "Schedule expression for inventory collection (minimum rate(30 minutes))."
  type        = string
  default     = "rate(30 minutes)"
}

variable "custom_inventory_schedule" {
  description = "Schedule expression for custom inventory collection."
  type        = string
  default     = "rate(1 hour)"
}

variable "inventory_bucket_prefix" {
  description = "Override for inventory S3 bucket name. Leave empty to auto-generate from project name and account ID."
  type        = string
  default     = ""
}

variable "inventory_data_expiration_days" {
  description = "Number of days before inventory data in S3 expires."
  type        = number
  default     = 90
}

variable "notification_email" {
  description = "Email address for SNS inventory notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "custom_app_name" {
  description = "Application name for the custom inventory entry."
  type        = string
  default     = "inventory-lab-app"
}

variable "custom_app_version" {
  description = "Application version for the custom inventory entry."
  type        = string
  default     = "1.0.0"
}
