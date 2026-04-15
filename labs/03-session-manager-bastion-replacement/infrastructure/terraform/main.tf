# -----------------------------------------------------------------------------
# Lab 03: Session Manager — Bastion Replacement
# Deploys: VPC with SSM endpoints (no NAT), KMS key, CloudWatch log group,
# S3 bucket for session logs, SSM Session Document, Parameter Store entries,
# EC2 instance in private subnet, EventBridge + SNS for session notifications.
# Demonstrates bastion-free architecture using VPC endpoints with full session
# logging, encryption, and IAM-based access control.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  param_prefix = "/${var.project_name}/${var.environment}"

  session_log_bucket_name = var.session_log_bucket_prefix != "" ? var.session_log_bucket_prefix : "${var.project_name}-${data.aws_caller_identity.current.account_id}-session-logs"

  cloudwatch_log_group = "/aws/ssm/session-logs/${var.project_name}"
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

# --- VPC (shared module — no NAT, SSM endpoints enabled) ---

module "ssm_vpc" {
  source = "../../../../shared/modules/ssm-vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  enable_nat_gateway   = false
  enable_ssm_endpoints = true

  common_tags = local.common_tags
}

# --- Additional VPC Endpoints (logs, s3, kms) ---

resource "aws_security_group" "additional_endpoints" {
  name_prefix = "${var.project_name}-endpoints-"
  description = "Allow HTTPS from VPC CIDR to additional VPC endpoints"
  vpc_id      = module.ssm_vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from VPC"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-additional-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = module.ssm_vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [module.ssm_vpc.private_subnet_id]
  security_group_ids  = [aws_security_group.additional_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.ssm_vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.id}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.ssm_vpc.private_rt_id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-s3-endpoint"
  })
}

resource "aws_vpc_endpoint" "kms" {
  vpc_id              = module.ssm_vpc.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.id}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [module.ssm_vpc.private_subnet_id]
  security_group_ids  = [aws_security_group.additional_endpoints.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-kms-endpoint"
  })
}

# --- KMS Key (session encryption + SecureString parameters) ---

resource "aws_kms_key" "session" {
  description             = "Customer-managed key for Session Manager encryption and SecureString parameters"
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
      },
      {
        Sid    = "AllowCloudWatchLogsEncryption"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.id}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:${local.cloudwatch_log_group}"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-key"
  })
}

resource "aws_kms_alias" "session" {
  name          = "alias/${var.project_name}-session-key"
  target_key_id = aws_kms_key.session.key_id
}

# --- CloudWatch Log Group (session transcripts) ---

resource "aws_cloudwatch_log_group" "session_logs" {
  name              = local.cloudwatch_log_group
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.session.arn

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-logs"
  })
}

# --- S3 Bucket (session logs — long-term retention) ---

resource "aws_s3_bucket" "session_logs" {
  bucket = local.session_log_bucket_name

  tags = merge(local.common_tags, {
    Name = local.session_log_bucket_name
  })
}

resource "aws_s3_bucket_versioning" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    expiration {
      days = var.session_log_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.session.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "session_logs" {
  bucket = aws_s3_bucket.session_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM Policy (instance role — session logging + parameter read) ---

resource "aws_iam_policy" "session_manager_instance" {
  name        = "${var.project_name}-session-manager-instance"
  description = "Allow EC2 instances to write session logs and read SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsDescribe"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "${aws_cloudwatch_log_group.session_logs.arn}:*"
      },
      {
        Sid    = "S3SessionLogWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = [
          aws_s3_bucket.session_logs.arn,
          "${aws_s3_bucket.session_logs.arn}/*",
        ]
      },
      {
        Sid    = "KMSSessionEncryption"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.session.arn
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter${local.param_prefix}/*"
      }
    ]
  })

  tags = local.common_tags
}

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name           = var.project_name
  additional_policy_arns = [aws_iam_policy.session_manager_instance.arn]
  common_tags            = local.common_tags
}

# --- SSM Session Document (account-level session preferences) ---

resource "aws_ssm_document" "session_preferences" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences for ${var.project_name}"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.session_logs.id
      s3KeyPrefix                 = "session-logs/"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.session_logs.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = aws_kms_key.session.arn
      idleSessionTimeout          = tostring(var.idle_session_timeout)
      maxSessionDuration          = tostring(var.max_session_duration)
      runAsEnabled                = var.run_as_enabled
      runAsDefaultUser            = var.run_as_default_user
      shellProfile = {
        linux = var.shell_profile_commands
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-preferences"
  })
}

# --- SSM Parameters (demo application config) ---

resource "aws_ssm_parameter" "idle_timeout" {
  name  = "${local.param_prefix}/config/idle-timeout"
  type  = "String"
  tier  = "Standard"
  value = tostring(var.idle_session_timeout)

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-config-idle-timeout"
  })
}

resource "aws_ssm_parameter" "allowed_commands" {
  name  = "${local.param_prefix}/config/allowed-commands"
  type  = "StringList"
  tier  = "Standard"
  value = "ls,cat,whoami,uname,df,free,top"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-config-allowed-commands"
  })
}

resource "aws_ssm_parameter" "db_password" {
  name   = "${local.param_prefix}/secrets/db-password"
  type   = "SecureString"
  tier   = "Standard"
  key_id = aws_kms_key.session.key_id
  value  = var.db_password

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-secrets-db-password"
  })
}

# --- EC2 Instance (session target — private subnet, no SSH) ---

resource "aws_instance" "session_target" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = module.ssm_vpc.private_subnet_id
  vpc_security_group_ids = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile   = module.ssm_instance_profile.instance_profile_name

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    param_prefix = local.param_prefix
    aws_region   = var.aws_region
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-target"
  })

  depends_on = [
    aws_vpc_endpoint.cloudwatch_logs,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.kms,
    aws_ssm_document.session_preferences,
    aws_ssm_parameter.idle_timeout,
    aws_ssm_parameter.allowed_commands,
    aws_ssm_parameter.db_password,
  ]
}

# --- SNS Topic (session notifications) ---

resource "aws_sns_topic" "session_notifications" {
  name = "${var.project_name}-session-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-notifications"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.session_notifications.arn

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
        Resource = aws_sns_topic.session_notifications.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.session_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- CloudTrail (required for EventBridge "AWS API Call via CloudTrail") ---

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.project_name}-${data.aws_caller_identity.current.account_id}-cloudtrail"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cloudtrail"
  })
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "CloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "management_events" {
  name                          = "${var.project_name}-management-events"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-management-events"
  })
}

# --- EventBridge: Session Start/Stop Events (via CloudTrail) ---

resource "aws_cloudwatch_event_rule" "session_activity" {
  name        = "${var.project_name}-session-activity"
  description = "Detect Session Manager start, resume, and terminate events via CloudTrail"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["ssm.amazonaws.com"]
      eventName   = ["StartSession", "TerminateSession", "ResumeSession"]
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-activity-rule"
  })
}

resource "aws_cloudwatch_event_target" "session_activity_sns" {
  rule      = aws_cloudwatch_event_rule.session_activity.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.session_notifications.arn
}

# --- CloudWatch Dashboard (session operations) ---

resource "aws_cloudwatch_dashboard" "session_operations" {
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
          title   = "Session Activity Events"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.session_activity.name]]
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
          title   = "Session Log Volume"
          region  = var.aws_region
          metrics = [["AWS/Logs", "IncomingLogEvents", "LogGroupName", aws_cloudwatch_log_group.session_logs.name]]
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
          title   = "Session Notifications Published"
          region  = var.aws_region
          metrics = [["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.session_notifications.name]]
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
          metrics = [["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.session_activity.name]]
          period  = 300
          stat    = "Sum"
          view    = "singleValue"
        }
      },
    ]
  })
}
