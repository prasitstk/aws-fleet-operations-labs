# --- VPC ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.ssm_vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.ssm_vpc.public_subnet_id
}

# --- EC2 ---

output "instance_ids" {
  description = "List of fleet node instance IDs"
  value       = aws_instance.fleet_node[*].id
}

output "instance_public_ips" {
  description = "List of fleet node public IP addresses"
  value       = aws_instance.fleet_node[*].public_ip
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ssm_instance_profile.instance_profile_name
}

# --- AMI ---

output "ami_id" {
  description = "ID of the AL2023 AMI used"
  value       = data.aws_ami.al2023.id
}

output "ami_name" {
  description = "Name of the AL2023 AMI used"
  value       = data.aws_ami.al2023.name
}

# --- KMS ---

output "kms_key_id" {
  description = "ID of the KMS key for Run Command encryption"
  value       = aws_kms_key.fleet_session.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for Run Command encryption"
  value       = aws_kms_key.fleet_session.arn
}

output "kms_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.fleet_session.name
}

# --- SSM ---

output "deploy_document_name" {
  description = "Name of the SSM Command document for deploying the financial collector"
  value       = aws_ssm_document.deploy_financial_collector.name
}

output "cw_agent_parameter_name" {
  description = "Name of the SSM parameter containing CloudWatch Agent config"
  value       = aws_ssm_parameter.cw_agent_config.name
}

# --- CloudWatch ---

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.fleet_performance.dashboard_name
}

output "log_group_name" {
  description = "Name of the CloudWatch log group for collector logs"
  value       = aws_cloudwatch_log_group.collector_logs.name
}

# --- SNS / EventBridge ---

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Run Command notifications"
  value       = aws_sns_topic.run_command_notifications.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for Run Command status changes"
  value       = aws_cloudwatch_event_rule.run_command_status.name
}

# --- Convenience ---

output "run_deploy_command" {
  description = "AWS CLI command to execute the deploy document on all fleet nodes"
  value       = "aws ssm send-command --document-name \"${aws_ssm_document.deploy_financial_collector.name}\" --targets Key=tag:Fleet,Values=financial-monitoring --region ${var.aws_region}"
}

output "app_urls" {
  description = "URLs to access the financial collector on each fleet node"
  value       = [for ip in aws_instance.fleet_node[*].public_ip : "http://${ip}:${var.app_port}/metrics"]
}
