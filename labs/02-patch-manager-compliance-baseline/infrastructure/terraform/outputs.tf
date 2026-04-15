# --- VPC ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.ssm_vpc.vpc_id
}

output "private_subnet_id" {
  description = "ID of the private subnet where patch target instances run"
  value       = module.ssm_vpc.private_subnet_id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway providing private subnet internet access"
  value       = module.ssm_vpc.nat_gw_id
}

# --- EC2 ---

output "patch_target_instance_ids" {
  description = "Instance IDs of the patch target EC2 instances"
  value       = aws_instance.patch_target[*].id
}

output "patch_target_private_ips" {
  description = "Private IP addresses of the patch target instances"
  value       = aws_instance.patch_target[*].private_ip
}

output "instance_profile_name" {
  description = "Name of the instance profile attached to patch targets"
  value       = module.ssm_instance_profile.instance_profile_name
}

# --- Patch Manager ---

output "patch_baseline_id" {
  description = "ID of the custom patch baseline"
  value       = aws_ssm_patch_baseline.al2023_security.id
}

output "patch_baseline_name" {
  description = "Name of the custom patch baseline"
  value       = aws_ssm_patch_baseline.al2023_security.name
}

output "patch_group_name" {
  description = "Name of the patch group"
  value       = aws_ssm_patch_group.linux_patch_group.patch_group
}

# --- Maintenance Window ---

output "maintenance_window_id" {
  description = "ID of the maintenance window"
  value       = aws_ssm_maintenance_window.patching.id
}

output "maintenance_window_name" {
  description = "Name of the maintenance window"
  value       = aws_ssm_maintenance_window.patching.name
}

# --- S3 ---

output "patch_log_bucket_name" {
  description = "Name of the S3 bucket for patch execution logs"
  value       = aws_s3_bucket.patch_logs.id
}

output "patch_log_bucket_arn" {
  description = "ARN of the S3 bucket for patch execution logs"
  value       = aws_s3_bucket.patch_logs.arn
}

# --- SNS ---

output "sns_topic_arn" {
  description = "ARN of the SNS topic for patch compliance notifications"
  value       = aws_sns_topic.patch_notifications.arn
}

# --- EventBridge ---

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for patch compliance changes"
  value       = aws_cloudwatch_event_rule.patch_compliance_change.name
}

# --- AMI ---

output "ami_id" {
  description = "AMI ID used for patch target instances"
  value       = data.aws_ami.al2023.id
}

output "ami_name" {
  description = "Name of the AMI used for patch target instances"
  value       = data.aws_ami.al2023.name
}

# --- CloudWatch ---

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for patch operations"
  value       = aws_cloudwatch_dashboard.patch_operations.dashboard_name
}
