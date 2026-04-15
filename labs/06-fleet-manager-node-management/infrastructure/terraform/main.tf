# -----------------------------------------------------------------------------
# Lab 06: Fleet Manager — Node Management
# Deploys: VPC with public subnet (no NAT/endpoints), 2x EC2 fleet nodes,
# CloudWatch Agent for enhanced monitoring, custom SSM Command document for
# financial collector deployment, KMS key, CloudWatch dashboard, and
# EventBridge + SNS for Run Command notifications.
# Demonstrates Fleet Manager's operational management capabilities: Run Command
# at scale, CloudWatch Agent for fleet-wide performance monitoring, and
# centralized dashboards — differentiating from Lab 03 (session security).
# -----------------------------------------------------------------------------

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  cw_agent_config_param_name = "AmazonCloudWatch-${var.project_name}"
  cw_log_group_name          = "/aws/ssm/${var.project_name}/collector"
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

# --- VPC (shared module — public subnet only, no NAT, no VPC endpoints) ---

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

# --- Security Group Rule (app ingress on port 8080) ---

resource "aws_security_group_rule" "app_ingress" {
  type              = "ingress"
  from_port         = var.app_port
  to_port           = var.app_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow inbound HTTP to financial collector"
  security_group_id = module.ssm_vpc.instance_sg_id
}

# --- IAM Policy (fleet node permissions) ---

resource "aws_iam_policy" "fleet_manager_instance" {
  name        = "${var.project_name}-fleet-instance"
  description = "Allow EC2 fleet nodes to publish CloudWatch metrics/logs and read SSM parameters"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchPutMetricData"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:log-group:${local.cw_log_group_name}:*"
      },
      {
        Sid    = "SSMParameterRead"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
        ]
        Resource = "arn:aws:ssm:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:parameter/${local.cw_agent_config_param_name}"
      },
      {
        Sid    = "EC2DescribeForCWAgent"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
        ]
        Resource = "*"
      },
    ]
  })

  tags = local.common_tags
}

# --- Instance Profile (shared module) ---

module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name = var.project_name
  additional_policy_arns = [
    aws_iam_policy.fleet_manager_instance.arn,
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]
  common_tags = local.common_tags
}

# --- EC2 Fleet Nodes ---

resource "aws_instance" "fleet_node" {
  count = var.instance_count

  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = module.ssm_vpc.public_subnet_id
  vpc_security_group_ids      = [module.ssm_vpc.instance_sg_id]
  iam_instance_profile        = module.ssm_instance_profile.instance_profile_name
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    cw_agent_config_param = local.cw_agent_config_param_name
    aws_region            = var.aws_region
    app_port              = var.app_port
    project_name          = var.project_name
  })

  tags = merge(local.common_tags, {
    Name  = "${var.project_name}-node-${count.index + 1}"
    Fleet = "financial-monitoring"
  })
}

# --- KMS Key (Run Command output encryption) ---

resource "aws_kms_key" "fleet_session" {
  description             = "Customer-managed key for Fleet Manager Run Command output encryption"
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
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-session-key"
  })
}

resource "aws_kms_alias" "fleet_session" {
  name          = "alias/${var.project_name}-session-key"
  target_key_id = aws_kms_key.fleet_session.key_id
}

# --- CloudWatch Agent Config via SSM Parameter Store ---

resource "aws_ssm_parameter" "cw_agent_config" {
  name = local.cw_agent_config_param_name
  type = "String"
  tier = "Standard"
  value = templatefile("${path.module}/cw_agent_config.json.tftpl", {
    collection_interval = var.cw_agent_collection_interval
    namespace           = "${var.project_name}/Fleet"
    log_group_name      = local.cw_log_group_name
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cw-agent-config"
  })
}

# --- CloudWatch Log Group (collector application logs) ---

resource "aws_cloudwatch_log_group" "collector_logs" {
  name              = local.cw_log_group_name
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-collector-logs"
  })
}

# --- Custom SSM Command Document (deploy financial collector) ---

resource "aws_ssm_document" "deploy_financial_collector" {
  name            = "${var.project_name}-deploy-financial-collector"
  document_type   = "Command"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "2.2"
    description   = "Deploy financial metrics collector application to fleet nodes"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "installDependencies"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "echo '=== Installing dependencies ==='",
            "dnf install -y python3 python3-pip",
            "echo '=== Dependencies installed ==='",
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "deployCollector"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "echo '=== Deploying financial collector ==='",
            "mkdir -p /opt/financial-collector",
            "mkdir -p /var/log/financial-collector",
            "cat > /opt/financial-collector/app.py << 'PYEOF'",
            "import http.server",
            "import json",
            "import random",
            "import time",
            "import logging",
            "import os",
            "",
            "logging.basicConfig(",
            "    filename='/var/log/financial-collector/app.log',",
            "    level=logging.INFO,",
            "    format='%(asctime)s %(levelname)s %(message)s'",
            ")",
            "",
            "START_TIME = time.time()",
            "PORT = int(os.environ.get('APP_PORT', '8080'))",
            "",
            "class MetricsHandler(http.server.BaseHTTPRequestHandler):",
            "    def do_GET(self):",
            "        if self.path == '/metrics':",
            "            metrics = {",
            "                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),",
            "                'stock_prices': {",
            "                    'AAPL': round(random.uniform(170, 195), 2),",
            "                    'GOOGL': round(random.uniform(140, 165), 2),",
            "                    'MSFT': round(random.uniform(380, 420), 2),",
            "                    'AMZN': round(random.uniform(175, 195), 2),",
            "                },",
            "                'portfolio_value': round(random.uniform(95000, 105000), 2),",
            "                'trade_volume': random.randint(1000, 5000),",
            "                'market_status': 'open' if random.random() > 0.3 else 'closed',",
            "            }",
            "            self._respond(200, metrics)",
            "            logging.info('Served /metrics request')",
            "        elif self.path == '/health':",
            "            health = {",
            "                'status': 'healthy',",
            "                'uptime_seconds': round(time.time() - START_TIME, 1),",
            "                'version': '1.0.0',",
            "            }",
            "            self._respond(200, health)",
            "        else:",
            "            self._respond(404, {'error': 'Not found'})",
            "",
            "    def _respond(self, code, data):",
            "        self.send_response(code)",
            "        self.send_header('Content-Type', 'application/json')",
            "        self.end_headers()",
            "        self.wfile.write(json.dumps(data, indent=2).encode())",
            "",
            "    def log_message(self, format, *args):",
            "        logging.info(format % args)",
            "",
            "if __name__ == '__main__':",
            "    server = http.server.HTTPServer(('0.0.0.0', PORT), MetricsHandler)",
            "    logging.info(f'Financial collector starting on port {PORT}')",
            "    print(f'Serving on port {PORT}')",
            "    server.serve_forever()",
            "PYEOF",
            "chmod +x /opt/financial-collector/app.py",
            "echo '=== Collector deployed ==='",
          ]
        }
      },
      {
        action = "aws:runShellScript"
        name   = "createService"
        inputs = {
          runCommand = [
            "#!/bin/bash",
            "set -euo pipefail",
            "echo '=== Creating systemd service ==='",
            "cat > /etc/systemd/system/financial-collector.service << 'SVCEOF'",
            "[Unit]",
            "Description=Financial Metrics Collector",
            "After=network.target",
            "",
            "[Service]",
            "Type=simple",
            "Environment=APP_PORT=8080",
            "ExecStart=/usr/bin/python3 /opt/financial-collector/app.py",
            "Restart=always",
            "RestartSec=5",
            "StandardOutput=journal",
            "StandardError=journal",
            "",
            "[Install]",
            "WantedBy=multi-user.target",
            "SVCEOF",
            "systemctl daemon-reload",
            "systemctl enable financial-collector",
            "systemctl start financial-collector",
            "echo '=== Service created and started ==='",
            "systemctl status financial-collector --no-pager",
          ]
        }
      },
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-deploy-financial-collector"
  })
}

# --- CloudWatch Dashboard (fleet performance) ---

resource "aws_cloudwatch_dashboard" "fleet_performance" {
  dashboard_name = "${var.project_name}-fleet-performance"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: CPU and Memory
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "CPU Utilization per Instance"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            for i, inst in aws_instance.fleet_node : [
              "${var.project_name}/Fleet", "cpu_usage_user",
              "InstanceId", inst.id,
              "cpu", "cpu-total",
              { label = "Node ${i + 1} - User" }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory Usage per Instance"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            for i, inst in aws_instance.fleet_node : [
              "${var.project_name}/Fleet", "mem_used_percent",
              "InstanceId", inst.id,
              { label = "Node ${i + 1}" }
            ]
          ]
        }
      },
      # Row 2: Disk I/O and Network
      # diskio metrics include a "name" dimension (device name) and net metrics
      # include an "interface" dimension — use SEARCH expressions to aggregate
      # across all devices/interfaces per instance.
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Disk I/O per Instance"
          view    = "timeSeries"
          region  = var.aws_region
          period  = 300
          stacked = true
          metrics = concat(
            [for i, inst in aws_instance.fleet_node : [
              { expression = "SEARCH('{${var.project_name}/Fleet,InstanceId,name} MetricName=\"diskio_reads\" InstanceId=\"${inst.id}\"', 'Sum', 300)", id = "reads${i}", label = "Node ${i + 1} - Reads" }
            ]],
            [for i, inst in aws_instance.fleet_node : [
              { expression = "SEARCH('{${var.project_name}/Fleet,InstanceId,name} MetricName=\"diskio_writes\" InstanceId=\"${inst.id}\"', 'Sum', 300)", id = "writes${i}", label = "Node ${i + 1} - Writes" }
            ]],
          )
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Network Traffic per Instance"
          view   = "timeSeries"
          region = var.aws_region
          period = 300
          metrics = concat(
            [for i, inst in aws_instance.fleet_node : [
              { expression = "SEARCH('{${var.project_name}/Fleet,InstanceId,interface} MetricName=\"net_bytes_sent\" InstanceId=\"${inst.id}\"', 'Sum', 300)", id = "sent${i}", label = "Node ${i + 1} - Sent" }
            ]],
            [for i, inst in aws_instance.fleet_node : [
              { expression = "SEARCH('{${var.project_name}/Fleet,InstanceId,interface} MetricName=\"net_bytes_recv\" InstanceId=\"${inst.id}\"', 'Sum', 300)", id = "recv${i}", label = "Node ${i + 1} - Recv" }
            ]],
          )
        }
      },
      # Row 3: Fleet summary (single value widgets)
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 4
        properties = {
          title  = "Fleet Average CPU Usage"
          view   = "singleValue"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            for i, inst in aws_instance.fleet_node : [
              "${var.project_name}/Fleet", "cpu_usage_user",
              "InstanceId", inst.id,
              "cpu", "cpu-total",
              { label = "Node ${i + 1}" }
            ]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 4
        properties = {
          title  = "Fleet Average Memory Usage"
          view   = "singleValue"
          region = var.aws_region
          period = 300
          stat   = "Average"
          metrics = [
            for i, inst in aws_instance.fleet_node : [
              "${var.project_name}/Fleet", "mem_used_percent",
              "InstanceId", inst.id,
              { label = "Node ${i + 1}" }
            ]
          ]
        }
      },
    ]
  })
}

# --- SNS Topic (Run Command notifications) ---

resource "aws_sns_topic" "run_command_notifications" {
  name = "${var.project_name}-run-command-notifications"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-run-command-notifications"
  })
}

resource "aws_sns_topic_policy" "eventbridge_publish" {
  arn = aws_sns_topic.run_command_notifications.arn

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
        Resource = aws_sns_topic.run_command_notifications.arn
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.run_command_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- EventBridge (Run Command status change — native SSM events) ---

resource "aws_cloudwatch_event_rule" "run_command_status" {
  name        = "${var.project_name}-run-command-status"
  description = "Detect Run Command status changes (native SSM event, no CloudTrail needed)"

  event_pattern = jsonencode({
    source      = ["aws.ssm"]
    detail-type = ["EC2 Command Status-change Notification", "EC2 Command Invocation Status-change Notification"]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-run-command-status-rule"
  })
}

resource "aws_cloudwatch_event_target" "run_command_sns" {
  rule      = aws_cloudwatch_event_rule.run_command_status.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.run_command_notifications.arn
}
