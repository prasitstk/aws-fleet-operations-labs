# -----------------------------------------------------------------------------
# Lab 07: Bedrock Session Log Analysis
# Deploys: VPC with EC2 instance (public subnet, SSM-managed), S3 bucket for
# session logs, SSM Session Document, Lambda function triggered by S3 PUT events
# that invokes Amazon Bedrock (Claude Haiku 4.5) to analyze session transcripts,
# enriches analysis with CloudTrail session metadata, and publishes security-
# focused reports via SNS. CloudWatch dashboard for pipeline observability.
# Demonstrates AI-powered operational log analysis as the SSM labs capstone.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  session_log_bucket_name = (
    var.session_log_bucket_prefix != ""
    ? var.session_log_bucket_prefix
    : "${var.project_name}-${data.aws_caller_identity.current.account_id}-session-logs"
  )

  lambda_function_name  = "${var.project_name}-analyzer"
  lambda_log_group_name = "/aws/lambda/${local.lambda_function_name}"
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

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/lambda/session_log_analyzer"
  output_path = "${path.module}/../../src/lambda/session_log_analyzer.zip"
}

# --- VPC (shared module — public subnet, no NAT, no VPC endpoints) ---

module "ssm_vpc" {
  source = "../../../../shared/modules/ssm-vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  enable_nat_gateway   = false
  enable_ssm_endpoints = false

  common_tags = local.common_tags
}

# --- IAM Policy (EC2 instance — session log write to S3) ---

resource "aws_iam_policy" "session_logging_instance" {
  name        = "${var.project_name}-session-logging-instance"
  description = "Allow EC2 instances to write Session Manager logs to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SessionLogWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = [
          "arn:aws:s3:::${local.session_log_bucket_name}",
          "arn:aws:s3:::${local.session_log_bucket_name}/*",
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
  additional_policy_arns = [aws_iam_policy.session_logging_instance.arn]
  common_tags            = local.common_tags
}

# --- EC2 Instance (session target — public subnet, SSM-managed) ---

resource "aws_instance" "session_target" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = module.ssm_vpc.public_subnet_id
  vpc_security_group_ids      = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile        = module.ssm_instance_profile.instance_profile_name
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-target"
  })

  depends_on = [
    aws_s3_bucket.session_logs,
  ]
}

# --- S3 Bucket (session logs) ---

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
      sse_algorithm = "AES256"
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

# --- SSM Session Document (account-level session preferences) ---
# Note: SSM-SessionManagerRunShell is an account singleton per region.
# Set create_session_document = false if Lab 03 is already deployed.

resource "aws_ssm_document" "session_preferences" {
  count           = var.create_session_document ? 1 : 0
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
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = false
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      runAsEnabled                = false
      runAsDefaultUser            = "ssm-user"
      shellProfile = {
        linux = "cd ~ && exec bash"
      }
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-preferences"
  })
}

# --- CloudTrail (for Lambda to query StartSession events) ---

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

# --- Lambda IAM Role and Policy ---

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-role"
  })
}

resource "aws_iam_policy" "lambda_execution" {
  name        = "${var.project_name}-lambda-policy"
  description = "Lambda permissions for session log analysis (S3, Bedrock, CloudTrail, SNS, CloudWatch Logs)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:${local.lambda_log_group_name}:*"
      },
      {
        Sid    = "S3ReadSessionLogs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.session_logs.arn}/*"
      },
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:GetInferenceProfile",
        ]
        Resource = [
          "arn:aws:bedrock:*:*:inference-profile/${var.bedrock_model_id}",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
        ]
      },
      {
        Sid    = "CloudTrailLookup"
        Effect = "Allow"
        Action = [
          "cloudtrail:LookupEvents",
        ]
        Resource = "*"
      },
      {
        Sid    = "SNSPublish"
        Effect = "Allow"
        Action = [
          "sns:Publish",
        ]
        Resource = aws_sns_topic.analysis_results.arn
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.lambda_execution.arn
}

# --- CloudWatch Log Group (Lambda) ---

resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.lambda_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-lambda-logs"
  })
}

# --- Lambda Function ---

resource "aws_lambda_function" "session_analyzer" {
  function_name    = local.lambda_function_name
  description      = "Analyzes SSM Session Manager logs using Amazon Bedrock (Claude Haiku 4.5)"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  role             = aws_iam_role.lambda_execution.arn
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.analysis_results.arn
      MODEL_ID        = var.bedrock_model_id
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_execution,
  ]

  tags = merge(local.common_tags, {
    Name = local.lambda_function_name
  })
}

# --- S3 Event Notification → Lambda ---

resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "AllowS3Invoke"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.session_analyzer.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.session_logs.arn
  source_account = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket_notification" "session_log_trigger" {
  bucket = aws_s3_bucket.session_logs.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.session_analyzer.arn
    events              = ["s3:ObjectCreated:Put"]
    filter_prefix       = "session-logs/"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# --- SNS Topic (analysis results) ---

resource "aws_sns_topic" "analysis_results" {
  name = "${var.project_name}-analysis-results"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-analysis-results"
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.analysis_results.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- CloudWatch Dashboard (pipeline observability) ---

resource "aws_cloudwatch_dashboard" "analysis_pipeline" {
  dashboard_name = "${var.project_name}-pipeline"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Lambda Invocations"
          region  = var.aws_region
          metrics = [["AWS/Lambda", "Invocations", "FunctionName", local.lambda_function_name]]
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          title   = "Lambda Errors"
          region  = var.aws_region
          metrics = [["AWS/Lambda", "Errors", "FunctionName", local.lambda_function_name]]
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name, { stat = "Average", label = "Average" }],
            ["...", { stat = "Maximum", label = "Maximum" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6
        properties = {
          title  = "Lambda Duration Distribution"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", local.lambda_function_name, { stat = "p50", label = "p50" }],
            ["...", { stat = "p90", label = "p90" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
          period = 300
          view   = "timeSeries"
        }
      },
    ]
  })
}
