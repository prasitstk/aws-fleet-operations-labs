variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
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

variable "enable_nat_gateway" {
  description = "Whether to create a NAT gateway for private subnet internet access. Use for labs needing outbound internet (Lab 01, 02)."
  type        = bool
  default     = true
}

variable "enable_ssm_endpoints" {
  description = "Whether to create VPC endpoints for SSM (ssm, ssmmessages, ec2messages). Use for bastion-free architectures (Lab 03)."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Tags to apply to all resources created by this module."
  type        = map(string)
  default     = {}
}
