variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming, tagging, and parameter hierarchy."
  type        = string
  default     = "param-store-lab"
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
  description = "EC2 instance type for the application server."
  type        = string
  default     = "t2.micro"
}

variable "notification_email" {
  description = "Email address for SNS parameter change notifications. Leave empty to skip subscription."
  type        = string
  default     = ""
}

variable "db_connection_string" {
  description = "Database connection string stored as SecureString parameter (encrypted with KMS)."
  type        = string
  sensitive   = true
  default     = "postgresql://app_user:s3cur3P@ss@db.example.com:5432/appdb?sslmode=require"
}

variable "api_key" {
  description = "API key stored as SecureString parameter (encrypted with KMS)."
  type        = string
  sensitive   = true
  default     = "sk-demo-a1b2c3d4e5f6g7h8i9j0"
}

variable "cert_thumbprint" {
  description = "Certificate thumbprint for the Advanced tier parameter with expiration policy."
  type        = string
  default     = "AB:CD:EF:12:34:56:78:90:AB:CD:EF:12:34:56:78:90:AB:CD:EF:12"
}

variable "cert_expiry_date" {
  description = "Expiration date for the certificate parameter policy (ISO 8601 format). Use a fixed date to avoid plan diffs."
  type        = string
  default     = "2026-04-01T00:00:00.000Z"
}
