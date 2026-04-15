variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "ssm-patch-manager"
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
  description = "EC2 instance type for patch target instances."
  type        = string
  default     = "t2.micro"
}

variable "instance_count" {
  description = "Number of EC2 instances to create as patch targets (demonstrates fleet patching)."
  type        = number
  default     = 2
}

variable "ami_name_filter" {
  description = "Name filter for the AMI data source. Use 'al2023-ami-2023.0.*-x86_64' for an older AMI to demonstrate patching."
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "patch_group_name" {
  description = "Patch group name used for EC2 tag and baseline association. Case-sensitive."
  type        = string
  default     = "LinuxPatchGroup"
}

variable "patch_baseline_approval_days_critical" {
  description = "Auto-approval delay in days for Critical and Important severity patches."
  type        = number
  default     = 7
}

variable "patch_baseline_approval_days_other" {
  description = "Auto-approval delay in days for Medium and Low severity patches."
  type        = number
  default     = 14
}

variable "maintenance_window_schedule" {
  description = "Schedule expression for the maintenance window (cron or rate). Example: 'rate(24 hours)' or 'cron(0 2 ? * SUN *)'."
  type        = string
  default     = "rate(24 hours)"
}

variable "maintenance_window_duration" {
  description = "Duration of the maintenance window in hours."
  type        = number
  default     = 1
}

variable "maintenance_window_cutoff" {
  description = "Hours before the end of the maintenance window to stop scheduling new tasks."
  type        = number
  default     = 0
}

variable "patch_operation" {
  description = "Patch operation to perform: 'Scan' (check compliance only) or 'Install' (scan and apply patches)."
  type        = string
  default     = "Install"

  validation {
    condition     = contains(["Scan", "Install"], var.patch_operation)
    error_message = "patch_operation must be either 'Scan' or 'Install'."
  }
}

variable "notification_email" {
  description = "Email address for SNS patch compliance notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "patch_log_bucket_prefix" {
  description = "S3 bucket name prefix for patch execution logs. If empty, auto-generates '{project_name}-{account_id}-patch-logs'."
  type        = string
  default     = ""
}

variable "patch_log_expiration_days" {
  description = "Number of days before patch log objects expire in S3."
  type        = number
  default     = 90
}
