# --- VPC ---

output "vpc_id" {
  value = module.ssm_vpc.vpc_id
}

output "public_subnet_id" {
  value = module.ssm_vpc.public_subnet_id
}

# --- EC2 ---

output "instance_id" {
  value       = aws_instance.session_target.id
  description = "EC2 instance ID for Session Manager access"
}

output "instance_public_ip" {
  value       = aws_instance.session_target.public_ip
  description = "EC2 instance public IP"
}

output "instance_profile_name" {
  value = module.ssm_instance_profile.instance_profile_name
}

# --- AMI ---

output "ami_id" {
  value = data.aws_ami.al2023.id
}

output "ami_name" {
  value = data.aws_ami.al2023.name
}

# --- S3 ---

output "session_log_bucket_name" {
  value       = aws_s3_bucket.session_logs.id
  description = "S3 bucket storing Session Manager session logs"
}

output "session_log_bucket_arn" {
  value = aws_s3_bucket.session_logs.arn
}

# --- Lambda ---

output "lambda_function_name" {
  value       = aws_lambda_function.session_analyzer.function_name
  description = "Lambda function that analyzes session logs via Bedrock"
}

output "lambda_function_arn" {
  value = aws_lambda_function.session_analyzer.arn
}

output "lambda_log_group_name" {
  value       = aws_cloudwatch_log_group.lambda.name
  description = "CloudWatch log group for Lambda execution logs"
}

# --- Bedrock ---

output "bedrock_model_id" {
  value       = var.bedrock_model_id
  description = "Bedrock model used for session log analysis"
}

# --- SNS ---

output "sns_topic_arn" {
  value       = aws_sns_topic.analysis_results.arn
  description = "SNS topic for analysis result notifications"
}

# --- CloudWatch ---

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.analysis_pipeline.dashboard_name
}

# --- CloudTrail ---

output "cloudtrail_name" {
  value       = aws_cloudtrail.management_events.name
  description = "CloudTrail trail for session metadata enrichment"
}

# --- Session Manager ---

output "session_document_name" {
  value       = var.create_session_document ? aws_ssm_document.session_preferences[0].name : "SSM-SessionManagerRunShell (external)"
  description = "SSM Session Document name (managed externally if create_session_document = false)"
}

# --- Convenience ---

output "start_session_command" {
  value       = "aws ssm start-session --target ${aws_instance.session_target.id} --region ${var.aws_region}"
  description = "Ready-to-use CLI command to start a Session Manager session"
}

output "dashboard_url" {
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.analysis_pipeline.dashboard_name}"
  description = "Direct link to the CloudWatch pipeline dashboard"
}
