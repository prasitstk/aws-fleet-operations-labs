# --- VPC ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.ssm_vpc.vpc_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.ssm_vpc.private_subnet_id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway"
  value       = module.ssm_vpc.nat_gw_id
}

# --- EC2 ---

output "app_server_id" {
  description = "Instance ID of the application server"
  value       = aws_instance.app_server.id
}

output "app_server_private_ip" {
  description = "Private IP address of the application server"
  value       = aws_instance.app_server.private_ip
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ssm_instance_profile.instance_profile_name
}

# --- KMS ---

output "kms_key_id" {
  description = "ID of the KMS key for SecureString encryption"
  value       = aws_kms_key.parameter_store.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for SecureString encryption"
  value       = aws_kms_key.parameter_store.arn
}

output "kms_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.parameter_store.name
}

# --- SSM Parameters ---

output "parameter_prefix" {
  description = "Parameter Store path prefix for this lab"
  value       = local.param_prefix
}

output "parameter_names" {
  description = "Map of all SSM parameter names created by this lab"
  value = {
    instance_type   = aws_ssm_parameter.app_instance_type.name
    ami_id          = aws_ssm_parameter.app_ami_id.name
    environment     = aws_ssm_parameter.app_environment.name
    log_level       = aws_ssm_parameter.app_log_level.name
    feature_flags   = aws_ssm_parameter.app_feature_flags.name
    db_connection   = aws_ssm_parameter.app_db_connection.name
    api_key         = aws_ssm_parameter.app_api_key.name
    cert_thumbprint = aws_ssm_parameter.expiring_cert_thumbprint.name
  }
}

# --- SNS ---

output "sns_topic_arn" {
  description = "ARN of the SNS topic for parameter change notifications"
  value       = aws_sns_topic.parameter_changes.arn
}

# --- EventBridge ---

output "eventbridge_rule_parameter_change" {
  description = "Name of the EventBridge rule for parameter changes"
  value       = aws_cloudwatch_event_rule.parameter_change.name
}

output "eventbridge_rule_policy_action" {
  description = "Name of the EventBridge rule for parameter policy actions"
  value       = aws_cloudwatch_event_rule.parameter_policy_action.name
}

# --- CloudWatch ---

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for parameter operations"
  value       = aws_cloudwatch_dashboard.parameter_operations.dashboard_name
}
