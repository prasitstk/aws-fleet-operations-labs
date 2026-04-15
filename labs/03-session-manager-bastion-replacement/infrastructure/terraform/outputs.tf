# --- VPC ---

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.ssm_vpc.vpc_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.ssm_vpc.private_subnet_id
}

# --- EC2 ---

output "session_target_instance_id" {
  description = "Instance ID of the session target"
  value       = aws_instance.session_target.id
}

output "session_target_private_ip" {
  description = "Private IP address of the session target"
  value       = aws_instance.session_target.private_ip
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ssm_instance_profile.instance_profile_name
}

# --- Session Manager ---

output "session_document_name" {
  description = "Name of the SSM Session Manager document"
  value       = aws_ssm_document.session_preferences.name
}

# --- KMS ---

output "kms_key_id" {
  description = "ID of the KMS key for session encryption"
  value       = aws_kms_key.session.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key for session encryption"
  value       = aws_kms_key.session.arn
}

output "kms_alias" {
  description = "Alias of the KMS key"
  value       = aws_kms_alias.session.name
}

# --- CloudWatch ---

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for session logs"
  value       = aws_cloudwatch_log_group.session_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for session logs"
  value       = aws_cloudwatch_log_group.session_logs.arn
}

# --- S3 ---

output "session_log_bucket_name" {
  description = "Name of the S3 bucket for session logs"
  value       = aws_s3_bucket.session_logs.id
}

output "session_log_bucket_arn" {
  description = "ARN of the S3 bucket for session logs"
  value       = aws_s3_bucket.session_logs.arn
}

# --- SSM Parameters ---

output "parameter_prefix" {
  description = "Parameter Store path prefix for this lab"
  value       = local.param_prefix
}

output "parameter_names" {
  description = "Map of SSM parameter names created by this lab"
  value = {
    idle_timeout     = aws_ssm_parameter.idle_timeout.name
    allowed_commands = aws_ssm_parameter.allowed_commands.name
    db_password      = aws_ssm_parameter.db_password.name
  }
}

# --- SNS ---

output "sns_topic_arn" {
  description = "ARN of the SNS topic for session notifications"
  value       = aws_sns_topic.session_notifications.arn
}

# --- EventBridge ---

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for session activity"
  value       = aws_cloudwatch_event_rule.session_activity.name
}

# --- VPC Endpoints ---

output "vpc_endpoint_ids" {
  description = "Map of additional VPC endpoint IDs"
  value = {
    logs = aws_vpc_endpoint.cloudwatch_logs.id
    s3   = aws_vpc_endpoint.s3.id
    kms  = aws_vpc_endpoint.kms.id
  }
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

# --- Convenience ---

output "start_session_command" {
  description = "AWS CLI command to start a session to the target instance"
  value       = "aws ssm start-session --target ${aws_instance.session_target.id} --region ${var.aws_region}"
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for session operations"
  value       = aws_cloudwatch_dashboard.session_operations.dashboard_name
}
