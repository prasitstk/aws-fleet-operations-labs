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

output "linux_instance_id" {
  description = "Instance ID of the Linux inventory target"
  value       = aws_instance.linux_target.id
}

output "linux_instance_private_ip" {
  description = "Private IP address of the Linux inventory target"
  value       = aws_instance.linux_target.private_ip
}

output "windows_instance_id" {
  description = "Instance ID of the Windows inventory target"
  value       = aws_instance.windows_target.id
}

output "windows_instance_private_ip" {
  description = "Private IP address of the Windows inventory target"
  value       = aws_instance.windows_target.private_ip
}

output "instance_profile_name" {
  description = "Name of the instance profile"
  value       = module.ssm_instance_profile.instance_profile_name
}

# --- AMIs ---

output "linux_ami_id" {
  description = "AMI ID used for the Linux instance"
  value       = data.aws_ami.al2023.id
}

output "linux_ami_name" {
  description = "AMI name used for the Linux instance"
  value       = data.aws_ami.al2023.name
}

output "windows_ami_id" {
  description = "AMI ID used for the Windows instance"
  value       = data.aws_ami.windows2025.id
}

output "windows_ami_name" {
  description = "AMI name used for the Windows instance"
  value       = data.aws_ami.windows2025.name
}

# --- SSM Inventory ---

output "inventory_association_id" {
  description = "ID of the SSM Inventory collection association"
  value       = aws_ssm_association.inventory_collection.association_id
}

output "inventory_association_name" {
  description = "Name of the SSM Inventory collection association"
  value       = aws_ssm_association.inventory_collection.association_name
}

output "resource_data_sync_name" {
  description = "Name of the Resource Data Sync"
  value       = aws_ssm_resource_data_sync.inventory_to_s3.name
}

output "custom_inventory_document_name" {
  description = "Name of the custom inventory SSM document"
  value       = aws_ssm_document.custom_inventory.name
}

output "custom_inventory_association_id" {
  description = "ID of the custom inventory SSM association"
  value       = aws_ssm_association.custom_inventory.association_id
}

# --- S3 ---

output "inventory_bucket_name" {
  description = "Name of the S3 bucket for inventory data"
  value       = aws_s3_bucket.inventory.id
}

output "inventory_bucket_arn" {
  description = "ARN of the S3 bucket for inventory data"
  value       = aws_s3_bucket.inventory.arn
}

# --- SNS ---

output "sns_topic_arn" {
  description = "ARN of the SNS topic for inventory change notifications"
  value       = aws_sns_topic.inventory_notifications.arn
}

# --- EventBridge ---

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule for inventory changes"
  value       = aws_cloudwatch_event_rule.inventory_change.name
}

# --- CloudWatch ---

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard for inventory operations"
  value       = aws_cloudwatch_dashboard.inventory_operations.dashboard_name
}
