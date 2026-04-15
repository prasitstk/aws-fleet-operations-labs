# -----------------------------------------------------------------------------
# Lab 05: Inventory — Resource Data Sync
# Deploys: VPC, heterogeneous EC2 fleet (Linux + Windows), SSM Inventory
# association, Resource Data Sync to S3, custom inventory SSM document,
# EventBridge + SNS for inventory change notifications.
# Demonstrates cross-platform inventory collection, centralized data export,
# custom inventory types, and event-driven inventory change detection.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  inventory_bucket_name = var.inventory_bucket_prefix != "" ? var.inventory_bucket_prefix : "${var.project_name}-${data.aws_caller_identity.current.account_id}-inventory"
}

# --- Data Sources ---

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.linux_ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "windows2025" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.windows_ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- VPC (shared module) ---

module "ssm_vpc" {
  source = "../../../../shared/modules/ssm-vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  enable_nat_gateway   = true
  enable_ssm_endpoints = false

  common_tags = local.common_tags
}

# --- S3 Bucket (inventory data sync destination) ---

resource "aws_s3_bucket" "inventory" {
  bucket = local.inventory_bucket_name

  tags = merge(local.common_tags, {
    Name = local.inventory_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "inventory" {
  bucket = aws_s3_bucket.inventory.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "inventory" {
  bucket = aws_s3_bucket.inventory.id

  rule {
    id     = "expire-old-inventory-data"
    status = "Enabled"

    expiration {
      days = var.inventory_data_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "inventory" {
  bucket = aws_s3_bucket.inventory.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "inventory" {
  bucket = aws_s3_bucket.inventory.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "ssm_inventory" {
  bucket = aws_s3_bucket.inventory.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.inventory.arn
      },
      {
        Sid    = "SSMBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.inventory.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# --- IAM (inventory S3 write policy for instance role) ---

resource "aws_iam_policy" "inventory_s3_write" {
  name        = "${var.project_name}-inventory-s3-write"
  description = "Allow EC2 instances to write inventory data and execution logs to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3InventoryWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.inventory.arn,
          "${aws_s3_bucket.inventory.arn}/*",
        ]
      }
    ]
  })

  tags = local.common_tags
}

# --- IAM (custom inventory put-inventory permission for instance role) ---

resource "aws_iam_policy" "inventory_put" {
  name        = "${var.project_name}-inventory-put"
  description = "Allow EC2 instances to put custom inventory data via SSM API"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMPutInventory"
        Effect = "Allow"
        Action = [
          "ssm:PutInventory",
        ]
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name = var.project_name
  additional_policy_arns = [
    aws_iam_policy.inventory_s3_write.arn,
    aws_iam_policy.inventory_put.arn,
  ]
  common_tags = local.common_tags
}

# --- EC2 Instances (inventory targets) ---

resource "aws_instance" "linux_target" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.linux_instance_type
  subnet_id              = module.ssm_vpc.private_subnet_id
  vpc_security_group_ids = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile   = module.ssm_instance_profile.instance_profile_name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-linux-target"
    OS   = "Linux"
  })
}

resource "aws_instance" "windows_target" {
  ami                    = data.aws_ami.windows2025.id
  instance_type          = var.windows_instance_type
  subnet_id              = module.ssm_vpc.private_subnet_id
  vpc_security_group_ids = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile   = module.ssm_instance_profile.instance_profile_name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-windows-target"
    OS   = "Windows"
  })
}

# --- SSM Inventory Association (AWS-GatherSoftwareInventory) ---

resource "aws_ssm_association" "inventory_collection" {
  name                = "AWS-GatherSoftwareInventory"
  association_name    = "${var.project_name}-inventory-collection"
  schedule_expression = var.inventory_schedule

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  parameters = {
    applications                = "Enabled"
    awsComponents               = "Enabled"
    networkConfig               = "Enabled"
    windowsUpdates              = "Enabled"
    instanceDetailedInformation = "Enabled"
    services                    = "Enabled"
    windowsRoles                = "Enabled"
    customInventory             = "Enabled"
    billingInfo                 = "Enabled"
  }

  output_location {
    s3_bucket_name = aws_s3_bucket.inventory.id
    s3_key_prefix  = "execution-logs/"
    s3_region      = var.aws_region
  }

  depends_on = [
    aws_instance.linux_target,
    aws_instance.windows_target,
  ]
}

# --- Resource Data Sync (inventory to S3) ---

resource "aws_ssm_resource_data_sync" "inventory_to_s3" {
  name = "${var.project_name}-inventory-sync"

  s3_destination {
    bucket_name = aws_s3_bucket.inventory.id
    prefix      = "inventory-data/"
    region      = var.aws_region
    sync_format = "JsonSerDe"
  }

  depends_on = [aws_s3_bucket_policy.ssm_inventory]
}

# --- Custom Inventory SSM Document ---

resource "aws_ssm_document" "custom_inventory" {
  name            = "${var.project_name}-custom-inventory"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Collect custom application metadata and register as Custom:AppMetadata inventory type"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "collectCustomInventory"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "INSTANCE_ID=$(ec2-metadata -i | cut -d ' ' -f 2)",
            "REGION=$(ec2-metadata --availability-zone | cut -d ' ' -f 2 | sed 's/.$//')",
            "HOSTNAME_VAL=$(hostname)",
            "UPTIME=$(uptime -s)",
            "KERNEL=$(uname -r)",
            "CAPTURE_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "ITEMS=$(printf '[{\"TypeName\":\"Custom:AppMetadata\",\"SchemaVersion\":\"1.0\",\"CaptureTime\":\"%s\",\"Content\":[{\"ApplicationName\":\"${var.custom_app_name}\",\"ApplicationVersion\":\"${var.custom_app_version}\",\"Hostname\":\"%s\",\"KernelVersion\":\"%s\",\"UptimeSince\":\"%s\"}]}]' \\",
            "  \"$CAPTURE_TIME\" \"$HOSTNAME_VAL\" \"$KERNEL\" \"$UPTIME\")",
            "aws ssm put-inventory --instance-id \"$INSTANCE_ID\" --items \"$ITEMS\" --region \"$REGION\"",
          ]
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-custom-inventory"
  })
}

resource "aws_ssm_association" "custom_inventory" {
  name                = aws_ssm_document.custom_inventory.name
  association_name    = "${var.project_name}-custom-inventory"
  schedule_expression = var.custom_inventory_schedule

  targets {
    key    = "tag:OS"
    values = ["Linux"]
  }

  depends_on = [aws_instance.linux_target]
}

# --- SNS Topic (inventory change notifications) ---

resource "aws_sns_topic" "inventory_notifications" {
  name = "${var.project_name}-inventory-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-inventory-notifications"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.inventory_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.inventory_notifications.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.inventory_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- EventBridge: Inventory Resource State Change ---

resource "aws_cloudwatch_event_rule" "inventory_change" {
  name        = "${var.project_name}-inventory-change"
  description = "Detect SSM Inventory resource state changes"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Inventory Resource State Change"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-inventory-change-rule"
  })
}

resource "aws_cloudwatch_event_target" "inventory_change_sns" {
  rule      = aws_cloudwatch_event_rule.inventory_change.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.inventory_notifications.arn
}

# --- CloudWatch Dashboard (inventory operations) ---

resource "aws_cloudwatch_dashboard" "inventory_operations" {
  dashboard_name = "${var.project_name}-operations"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Inventory Change Events"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.inventory_change.name]]
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Inventory Notifications Published"
          region  = var.aws_region
          metrics = [["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.inventory_notifications.name]]
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "EventBridge Invocations"
          region  = var.aws_region
          metrics = [["AWS/Events", "Invocations", "RuleName", aws_cloudwatch_event_rule.inventory_change.name]]
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 4
        properties = {
          title   = "EventBridge Failed Invocations"
          region  = var.aws_region
          metrics = [["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.inventory_change.name]]
          period  = 300
          stat    = "Sum"
          view    = "singleValue"
        }
      },
    ]
  })
}
