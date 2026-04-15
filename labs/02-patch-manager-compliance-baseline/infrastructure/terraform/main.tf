# -----------------------------------------------------------------------------
# Lab 02: Patch Manager — Compliance Baseline
# Deploys: VPC, EC2 fleet, custom patch baseline, patch group, maintenance
# window with AWS-RunPatchBaseline task, S3 for patch logs, EventBridge + SNS
# for compliance change notifications.
# Demonstrates automated OS patching with tiered approval rules, fleet-wide
# compliance tracking, and event-driven alerting.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  patch_log_bucket_name = var.patch_log_bucket_prefix != "" ? var.patch_log_bucket_prefix : "${var.project_name}-${data.aws_caller_identity.current.account_id}-patch-logs"
}

# --- Data Sources ---

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
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

# --- S3 Bucket (patch execution logs) ---

resource "aws_s3_bucket" "patch_logs" {
  bucket = local.patch_log_bucket_name

  tags = merge(local.common_tags, {
    Name = local.patch_log_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = var.patch_log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "patch_logs" {
  bucket = aws_s3_bucket.patch_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM (patch log write policy for instance role) ---

resource "aws_iam_policy" "patch_log_write" {
  name        = "${var.project_name}-patch-log-write"
  description = "Allow EC2 instances to write patch execution logs to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3PatchLogWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.patch_logs.arn,
          "${aws_s3_bucket.patch_logs.arn}/*",
        ]
      }
    ]
  })

  tags = local.common_tags
}

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name           = var.project_name
  additional_policy_arns = [aws_iam_policy.patch_log_write.arn]
  common_tags            = local.common_tags
}

# --- EC2 Instances (patch targets) ---

resource "aws_instance" "patch_target" {
  count = var.instance_count

  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = module.ssm_vpc.private_subnet_id
  vpc_security_group_ids = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile   = module.ssm_instance_profile.instance_profile_name

  tags = merge(local.common_tags, {
    Name          = "${var.project_name}-target-${count.index + 1}"
    "Patch Group" = var.patch_group_name
  })
}

# --- Patch Manager: Custom Patch Baseline ---

resource "aws_ssm_patch_baseline" "al2023_security" {
  name             = "${var.project_name}-al2023-security"
  description      = "Custom patch baseline for Amazon Linux 2023 with tiered approval rules"
  operating_system = "AMAZON_LINUX_2023"

  # Tier 1: Critical and Important patches — shorter approval delay
  approval_rule {
    approve_after_days = var.patch_baseline_approval_days_critical
    compliance_level   = "CRITICAL"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Critical", "Important"]
    }
  }

  # Tier 2: Medium and Low severity — longer approval delay
  approval_rule {
    approve_after_days = var.patch_baseline_approval_days_other
    compliance_level   = "MEDIUM"

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["Security"]
    }

    patch_filter {
      key    = "SEVERITY"
      values = ["Medium", "Low"]
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-al2023-security"
  })
}

# --- Patch Manager: Patch Group Association ---

resource "aws_ssm_patch_group" "linux_patch_group" {
  baseline_id = aws_ssm_patch_baseline.al2023_security.id
  patch_group = var.patch_group_name
}

# --- Maintenance Window ---

resource "aws_ssm_maintenance_window" "patching" {
  name                       = "${var.project_name}-patching-window"
  schedule                   = var.maintenance_window_schedule
  duration                   = var.maintenance_window_duration
  cutoff                     = var.maintenance_window_cutoff
  allow_unassociated_targets = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-patching-window"
  })
}

# --- Maintenance Window Target (tag-based) ---

resource "aws_ssm_maintenance_window_target" "patch_group_instances" {
  window_id     = aws_ssm_maintenance_window.patching.id
  name          = "${var.project_name}-patch-group-targets"
  resource_type = "INSTANCE"

  targets {
    key    = "tag:Patch Group"
    values = [var.patch_group_name]
  }
}

# --- Maintenance Window IAM Role ---

resource "aws_iam_role" "maintenance_window" {
  name               = "${var.project_name}-mw-role"
  assume_role_policy = file("${path.module}/../../../../shared/policies/ssm-assume-role.json")

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-mw-role"
  })
}

resource "aws_iam_role_policy" "maintenance_window" {
  name = "${var.project_name}-mw-policy"
  role = aws_iam_role.maintenance_window.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSendCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation",
        ]
        Resource = "*"
      },
      {
        Sid    = "S3PatchLogWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation",
        ]
        Resource = [
          aws_s3_bucket.patch_logs.arn,
          "${aws_s3_bucket.patch_logs.arn}/*",
        ]
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.patch_notifications.arn
      },
    ]
  })
}

# --- Maintenance Window Task (AWS-RunPatchBaseline) ---

resource "aws_ssm_maintenance_window_task" "run_patch_baseline" {
  window_id        = aws_ssm_maintenance_window.patching.id
  name             = "${var.project_name}-run-patch-baseline"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  service_role_arn = aws_iam_role.maintenance_window.arn

  max_concurrency = "50%"
  max_errors      = "25%"

  targets {
    key    = "WindowTargetIds"
    values = [aws_ssm_maintenance_window_target.patch_group_instances.id]
  }

  task_invocation_parameters {
    run_command_parameters {
      comment              = "Patch baseline execution via maintenance window"
      timeout_seconds      = 600
      output_s3_bucket     = aws_s3_bucket.patch_logs.id
      output_s3_key_prefix = "patch-logs/"

      parameter {
        name   = "Operation"
        values = [var.patch_operation]
      }
    }
  }
}

# --- SNS Topic (patch compliance notifications) ---

resource "aws_sns_topic" "patch_notifications" {
  name = "${var.project_name}-patch-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-patch-notifications"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.patch_notifications.arn

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
        Resource = aws_sns_topic.patch_notifications.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.patch_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- EventBridge: Patch Compliance State Change ---

resource "aws_cloudwatch_event_rule" "patch_compliance_change" {
  name        = "${var.project_name}-patch-compliance-change"
  description = "Detect SSM Patch Manager compliance state changes"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Configuration Compliance State Change"]
    detail = {
      compliance-type = ["Patch"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-patch-compliance-change-rule"
  })
}

resource "aws_cloudwatch_event_target" "patch_compliance_sns" {
  rule      = aws_cloudwatch_event_rule.patch_compliance_change.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.patch_notifications.arn
}

# --- CloudWatch Dashboard (patch operations) ---

resource "aws_cloudwatch_dashboard" "patch_operations" {
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
          title   = "Patch Compliance Events"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.patch_compliance_change.name]]
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
          title   = "Patch Notifications Published"
          region  = var.aws_region
          metrics = [["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.patch_notifications.name]]
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
          metrics = [["AWS/Events", "Invocations", "RuleName", aws_cloudwatch_event_rule.patch_compliance_change.name]]
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
          metrics = [["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.patch_compliance_change.name]]
          period  = 300
          stat    = "Sum"
          view    = "singleValue"
        }
      },
    ]
  })
}
