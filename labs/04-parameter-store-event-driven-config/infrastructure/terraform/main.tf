# -----------------------------------------------------------------------------
# Lab 04: Parameter Store — Event-Driven Configuration
# Deploys: VPC, EC2 instance, KMS key, SSM parameters (all types/tiers),
# EventBridge rules for change detection, SNS for notifications.
# Demonstrates parameter hierarchy, SecureString encryption, Advanced tier
# policies, deploy-time vs runtime parameter resolution, and event-driven
# configuration change detection.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  param_prefix = "/${var.project_name}/${var.environment}"
}

# --- Data Sources ---

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
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

# --- KMS Key (for SecureString encryption) ---

resource "aws_kms_key" "parameter_store" {
  description             = "Customer-managed key for SSM Parameter Store SecureString parameters"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "RootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-parameter-store-key"
  })
}

resource "aws_kms_alias" "parameter_store" {
  name          = "alias/${var.project_name}-parameter-store"
  target_key_id = aws_kms_key.parameter_store.key_id
}

# --- IAM Policy (Parameter Store read + KMS decrypt for EC2) ---

resource "aws_iam_policy" "parameter_store_read" {
  name        = "${var.project_name}-parameter-store-read"
  description = "Allow reading SSM parameters and decrypting SecureString values"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${local.param_prefix}/*"
      },
      {
        Sid      = "KMSDecrypt"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = aws_kms_key.parameter_store.arn
      }
    ]
  })

  tags = local.common_tags
}

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name           = var.project_name
  additional_policy_arns = [aws_iam_policy.parameter_store_read.arn]
  common_tags            = local.common_tags
}

# --- SSM Parameters: String (Standard tier) ---

resource "aws_ssm_parameter" "app_instance_type" {
  name  = "${local.param_prefix}/ec2/instance-type"
  type  = "String"
  tier  = "Standard"
  value = var.instance_type

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-instance-type"
  })
}

resource "aws_ssm_parameter" "app_ami_id" {
  name      = "${local.param_prefix}/ec2/ami-id"
  type      = "String"
  tier      = "Standard"
  data_type = "aws:ec2:image"
  value     = data.aws_ami.al2023.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-ami-id"
  })
}

resource "aws_ssm_parameter" "app_environment" {
  name  = "${local.param_prefix}/app/environment"
  type  = "String"
  tier  = "Standard"
  value = var.environment

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-environment"
  })
}

resource "aws_ssm_parameter" "app_log_level" {
  name  = "${local.param_prefix}/app/log-level"
  type  = "String"
  tier  = "Standard"
  value = "INFO"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-log-level"
  })
}

# --- SSM Parameters: StringList (Standard tier) ---

resource "aws_ssm_parameter" "app_feature_flags" {
  name  = "${local.param_prefix}/app/feature-flags"
  type  = "StringList"
  tier  = "Standard"
  value = "enable-monitoring,enable-alerts"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-feature-flags"
  })
}

# --- SSM Parameters: SecureString (Standard tier, KMS-encrypted) ---

resource "aws_ssm_parameter" "app_db_connection" {
  name   = "${local.param_prefix}/secrets/db-connection-string"
  type   = "SecureString"
  tier   = "Standard"
  key_id = aws_kms_key.parameter_store.key_id
  value  = var.db_connection_string

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-secrets-db-connection"
  })
}

resource "aws_ssm_parameter" "app_api_key" {
  name   = "${local.param_prefix}/secrets/api-key"
  type   = "SecureString"
  tier   = "Standard"
  key_id = aws_kms_key.parameter_store.key_id
  value  = var.api_key

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-secrets-api-key"
  })
}

# --- SSM Parameters: Advanced tier (with parameter policies) ---

resource "aws_ssm_parameter" "expiring_cert_thumbprint" {
  name  = "${local.param_prefix}/advanced/cert-thumbprint"
  type  = "String"
  tier  = "Advanced"
  value = var.cert_thumbprint

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-advanced-cert-thumbprint"
  })
}

# Apply parameter policies via CLI (aws_ssm_parameter lacks native policy support)
resource "null_resource" "cert_thumbprint_policies" {
  triggers = {
    parameter_name  = aws_ssm_parameter.expiring_cert_thumbprint.name
    cert_expiry     = var.cert_expiry_date
    parameter_value = var.cert_thumbprint
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ssm put-parameter \
        --name "${aws_ssm_parameter.expiring_cert_thumbprint.name}" \
        --value "${var.cert_thumbprint}" \
        --type String \
        --tier Advanced \
        --overwrite \
        --policies '[
          {
            "Type": "Expiration",
            "Version": "1.0",
            "Attributes": {
              "Timestamp": "${var.cert_expiry_date}"
            }
          },
          {
            "Type": "ExpirationNotification",
            "Version": "1.0",
            "Attributes": {
              "Before": "15",
              "Unit": "Days"
            }
          },
          {
            "Type": "NoChangeNotification",
            "Version": "1.0",
            "Attributes": {
              "After": "7",
              "Unit": "Days"
            }
          }
        ]' \
        --region ${var.aws_region}
    EOT
  }

  depends_on = [aws_ssm_parameter.expiring_cert_thumbprint]
}

# --- EC2 Instance (reads parameters at boot) ---

resource "aws_instance" "app_server" {
  ami                    = aws_ssm_parameter.app_ami_id.value
  instance_type          = aws_ssm_parameter.app_instance_type.value
  subnet_id              = module.ssm_vpc.private_subnet_id
  vpc_security_group_ids = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile   = module.ssm_instance_profile.instance_profile_name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    param_prefix = local.param_prefix
    aws_region   = var.aws_region
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-server"
  })

  depends_on = [
    aws_ssm_parameter.app_log_level,
    aws_ssm_parameter.app_feature_flags,
    aws_ssm_parameter.app_db_connection,
    aws_ssm_parameter.app_api_key,
  ]
}

# --- SNS Topic (notification channel) ---

resource "aws_sns_topic" "parameter_changes" {
  name = "${var.project_name}-parameter-changes"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-parameter-changes"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.parameter_changes.arn

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
        Resource = aws_sns_topic.parameter_changes.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.parameter_changes.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- EventBridge: Parameter Store Change Events ---

resource "aws_cloudwatch_event_rule" "parameter_change" {
  name        = "${var.project_name}-parameter-change"
  description = "Detect Parameter Store changes under ${local.param_prefix}/"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Change"]
    detail = {
      name = [{
        prefix = "${local.param_prefix}/"
      }]
      operation = ["Create", "Update", "Delete", "LabelParameterVersion"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-parameter-change-rule"
  })
}

resource "aws_cloudwatch_event_target" "parameter_change_sns" {
  rule      = aws_cloudwatch_event_rule.parameter_change.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.parameter_changes.arn
}

# --- EventBridge: Parameter Policy Action Events ---

resource "aws_cloudwatch_event_rule" "parameter_policy_action" {
  name        = "${var.project_name}-parameter-policy-action"
  description = "Detect Parameter Store policy actions (expiration, no-change warnings)"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["Parameter Store Policy Action"]
    detail = {
      parameter-name = [{
        prefix = "${local.param_prefix}/"
      }]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-parameter-policy-action-rule"
  })
}

resource "aws_cloudwatch_event_target" "policy_action_sns" {
  rule      = aws_cloudwatch_event_rule.parameter_policy_action.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.parameter_changes.arn
}

# --- CloudWatch Dashboard (parameter operations) ---

resource "aws_cloudwatch_dashboard" "parameter_operations" {
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
          title   = "Parameter Change Events"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.parameter_change.name]]
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
          title   = "Policy Action Events"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.parameter_policy_action.name]]
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
          title   = "Change Notifications Published"
          region  = var.aws_region
          metrics = [["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.parameter_changes.name]]
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
          title  = "EventBridge Failed Invocations"
          region = var.aws_region
          metrics = [
            ["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.parameter_change.name],
            ["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.parameter_policy_action.name],
          ]
          period = 300
          stat   = "Sum"
          view   = "singleValue"
        }
      },
    ]
  })
}
