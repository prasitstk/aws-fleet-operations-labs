# -----------------------------------------------------------------------------
# Lab 01: Automation Runbook — EC2 Provisioning
# Deploys: VPC, instance profile, SSM Automation role, SSM runbook document.
# The runbook launches an EC2 instance, waits for running, installs Apache
# and Node.js via Run Command.
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- AMI Lookup (Amazon Linux 2023) ---

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

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name = var.project_name
  common_tags  = local.common_tags
}

# --- SSM Automation Role ---

resource "aws_iam_role" "ssm_automation" {
  name               = "${var.project_name}-automation-role"
  assume_role_policy = file("${path.module}/../../../../shared/policies/ssm-assume-role.json")

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-automation-role"
  })
}

resource "aws_iam_role_policy" "ssm_automation" {
  name = "${var.project_name}-automation-policy"
  role = aws_iam_role.ssm_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2RunInstances"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
        ]
        Resource = "*"
      },
      {
        Sid      = "PassRoleToEC2"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = module.ssm_instance_profile.role_arn
      },
      {
        Sid    = "SSMRunCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
        ]
        Resource = "*"
      },
    ]
  })
}

# --- SSM Automation Document (Runbook) ---

resource "aws_ssm_document" "ec2_provisioning_runbook" {
  name            = "${var.project_name}-ec2-provisioning"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Provision an EC2 instance and install Apache + Node.js via SSM Run Command."
    assumeRole    = "{{ AutomationAssumeRole }}"

    parameters = {
      AutomationAssumeRole = {
        type        = "String"
        description = "ARN of the IAM role for SSM Automation to assume."
        default     = aws_iam_role.ssm_automation.arn
      }
      ImageId = {
        type        = "String"
        description = "AMI ID for the EC2 instance (Amazon Linux 2023)."
        default     = data.aws_ami.al2023.id
      }
      InstanceType = {
        type        = "String"
        description = "EC2 instance type."
        default     = var.instance_type
      }
      SubnetId = {
        type        = "String"
        description = "Subnet ID for the EC2 instance (private subnet with NAT)."
        default     = module.ssm_vpc.private_subnet_id
      }
      IamInstanceProfileName = {
        type        = "String"
        description = "Name of the IAM instance profile for SSM Agent connectivity."
        default     = module.ssm_instance_profile.instance_profile_name
      }
      SecurityGroupId = {
        type        = "String"
        description = "Security group ID for the EC2 instance."
        default     = module.ssm_vpc.instance_sg_id
      }
      InstanceName = {
        type        = "String"
        description = "Name tag for the provisioned EC2 instance."
        default     = "${var.project_name}-provisioned"
      }
    }

    mainSteps = [
      {
        name   = "RunInstances"
        action = "aws:runInstances"
        inputs = {
          ImageId                = "{{ ImageId }}"
          InstanceType           = "{{ InstanceType }}"
          SubnetId               = "{{ SubnetId }}"
          IamInstanceProfileName = "{{ IamInstanceProfileName }}"
          SecurityGroupIds       = ["{{ SecurityGroupId }}"]
          MinInstanceCount       = 1
          MaxInstanceCount       = 1
          TagSpecifications = [
            {
              ResourceType = "instance"
              Tags = [
                { Key = "Name", Value = "{{ InstanceName }}" },
                { Key = "ManagedBy", Value = "ssm-automation" },
                { Key = "Project", Value = var.project_name },
                { Key = "Environment", Value = var.environment },
              ]
            },
          ]
        }
      },
      {
        name   = "WaitForInstanceRunning"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service          = "ec2"
          Api              = "DescribeInstanceStatus"
          InstanceIds      = ["{{ RunInstances.InstanceIds }}"]
          PropertySelector = "$.InstanceStatuses[0].InstanceState.Name"
          DesiredValues    = ["running"]
        }
      },
      {
        name   = "InstallApache"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds  = ["{{ RunInstances.InstanceIds }}"]
          Parameters = {
            commands = [
              "sudo dnf install -y httpd",
              "sudo systemctl enable httpd",
              "sudo systemctl start httpd",
            ]
          }
        }
      },
      {
        name   = "InstallNode"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds  = ["{{ RunInstances.InstanceIds }}"]
          Parameters = {
            commands = [
              "sudo dnf install -y nodejs",
              "node --version",
            ]
          }
        }
      },
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ec2-provisioning"
  })
}

# --- SNS Topic (automation notifications) ---

resource "aws_sns_topic" "automation_notifications" {
  name = "${var.project_name}-automation-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-automation-notifications"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.automation_notifications.arn

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
        Resource = aws_sns_topic.automation_notifications.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.automation_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- EventBridge: Automation Execution Status Change ---

resource "aws_cloudwatch_event_rule" "automation_execution" {
  name        = "${var.project_name}-automation-execution"
  description = "Detect SSM Automation execution status changes"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["EC2 Automation Execution Status-change Notification"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-automation-execution-rule"
  })
}

resource "aws_cloudwatch_event_target" "automation_sns" {
  rule      = aws_cloudwatch_event_rule.automation_execution.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.automation_notifications.arn
}

# --- CloudWatch Dashboard (automation operations) ---

resource "aws_cloudwatch_dashboard" "automation_operations" {
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
          title   = "Automation Events Matched"
          region  = var.aws_region
          metrics = [["AWS/Events", "MatchedEvents", "RuleName", aws_cloudwatch_event_rule.automation_execution.name]]
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
          title   = "SNS Notifications Published"
          region  = var.aws_region
          metrics = [["AWS/SNS", "NumberOfMessagesPublished", "TopicName", aws_sns_topic.automation_notifications.name]]
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
          metrics = [["AWS/Events", "Invocations", "RuleName", aws_cloudwatch_event_rule.automation_execution.name]]
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
          metrics = [["AWS/Events", "FailedInvocations", "RuleName", aws_cloudwatch_event_rule.automation_execution.name]]
          period  = 300
          stat    = "Sum"
          view    = "singleValue"
        }
      },
    ]
  })
}
