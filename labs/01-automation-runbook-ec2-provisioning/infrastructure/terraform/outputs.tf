output "vpc_id" {
  description = "ID of the VPC"
  value       = module.ssm_vpc.vpc_id
}

output "private_subnet_id" {
  description = "ID of the private subnet where runbook instances are launched"
  value       = module.ssm_vpc.private_subnet_id
}

output "instance_sg_id" {
  description = "ID of the instance security group"
  value       = module.ssm_vpc.instance_sg_id
}

output "instance_profile_name" {
  description = "Name of the instance profile attached to runbook-launched instances"
  value       = module.ssm_instance_profile.instance_profile_name
}

output "instance_profile_arn" {
  description = "ARN of the instance profile"
  value       = module.ssm_instance_profile.instance_profile_arn
}

output "automation_role_arn" {
  description = "ARN of the SSM Automation role"
  value       = aws_iam_role.ssm_automation.arn
}

output "runbook_name" {
  description = "Name of the SSM Automation runbook document"
  value       = aws_ssm_document.ec2_provisioning_runbook.name
}

output "runbook_arn" {
  description = "ARN of the SSM Automation runbook document"
  value       = aws_ssm_document.ec2_provisioning_runbook.arn
}

output "ami_id" {
  description = "AMI ID used as default for the runbook (Amazon Linux 2023)"
  value       = data.aws_ami.al2023.id
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway providing private subnet internet access"
  value       = module.ssm_vpc.nat_gw_id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for automation notifications"
  value       = aws_sns_topic.automation_notifications.arn
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for automation execution status changes"
  value       = aws_cloudwatch_event_rule.automation_execution.name
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.automation_operations.dashboard_name
}
