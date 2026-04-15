# AWS Fleet Operations Labs

![Terraform CI](https://github.com/prasitstk/aws-fleet-operations-labs/actions/workflows/terraform-ci.yml/badge.svg)

A collection of AWS Systems Manager fleet operations labs built entirely with Terraform. Follow the fleet operations lifecycle from provisioning through AI-powered log analysis: Automation runbooks, Patch Manager compliance, Session Manager secure access, Parameter Store configuration, Inventory resource sync, Fleet Manager node management, and Bedrock session analysis. Designed as a progressive series that tells a complete fleet operations story.

---

## Labs

| # | Lab | Description | Key Services |
|---|-----|-------------|--------------|
| 01 | [Automation Runbook — EC2 Provisioning](labs/01-automation-runbook-ec2-provisioning/) | Multi-step SSM Automation runbook that launches an EC2 instance, waits for readiness, and installs Apache + Node.js via Run Command | SSM Automation, EC2, IAM |
| 02 | [Patch Manager — Compliance Baseline](labs/02-patch-manager-compliance-baseline/) | Custom patch baseline with tiered approval rules, patch groups, maintenance windows, and event-driven compliance notifications | SSM Patch Manager, EventBridge, SNS, S3 |
| 03 | [Session Manager — Bastion Replacement](labs/03-session-manager-bastion-replacement/) | Secure interactive access via VPC endpoints (no bastion host), with KMS-encrypted CloudWatch + S3 logging and session lifecycle notifications | SSM Session Manager, VPC Endpoints, KMS, CloudWatch Logs, CloudTrail |
| 04 | [Parameter Store — Event-Driven Config](labs/04-parameter-store-event-driven-config/) | Hierarchical parameters (String, StringList, SecureString, Advanced tier) with KMS encryption, parameter policies, and EventBridge change detection | SSM Parameter Store, KMS, EventBridge, SNS |
| 05 | [Inventory — Resource Data Sync](labs/05-inventory-resource-data-sync/) | Heterogeneous fleet inventory (Linux + Windows), Resource Data Sync to S3, custom inventory SSM document, and inventory state change notifications | SSM Inventory, Resource Data Sync, S3, EventBridge, SNS |
| 06 | [Fleet Manager — Node Management](labs/06-fleet-manager-node-management/) | Fleet-wide node management with custom SSM Command document deploying a financial metrics collector, CloudWatch Agent, and fleet performance dashboard | SSM Fleet Manager, Run Command, CloudWatch Agent, CloudWatch Dashboard |
| 07 | [Bedrock Session Log Analysis](labs/07-bedrock-session-log-analysis/) | AI-powered session log analysis using Lambda + Bedrock Claude Haiku 4.5, triggered by S3 PUT events, enriched with CloudTrail metadata | Lambda, Bedrock, S3, CloudTrail, SNS, CloudWatch Dashboard |

Each lab includes a detailed README with architecture diagram, deployment steps, validation commands, and cost estimate.

---

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with appropriate credentials
- An AWS account with permissions for SSM, EC2, VPC, IAM, S3, KMS, EventBridge, SNS, CloudWatch, Lambda
- Amazon Bedrock access with Claude Haiku 4.5 enabled (Lab 07 only)
- [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for AWS CLI (Lab 03)
- Default region: `us-east-1`

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/prasitstk/aws-fleet-operations-labs.git
cd aws-fleet-operations-labs

# Pick a lab
cd labs/01-automation-runbook-ec2-provisioning/infrastructure/terraform

# Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed

# Deploy
terraform init
terraform plan
terraform apply

# Clean up (avoid ongoing charges)
terraform destroy
```

---

## Local Validation

Run the validation script before pushing to catch formatting and syntax issues locally (the same checks that CI runs on GitHub):

```bash
# From the repo root
bash tests/validate.sh
```

This finds every Terraform directory under `shared/modules/` and `labs/`, then runs `terraform init`, `fmt -check`, and `validate` on each. Expected output when everything passes:

```
=== Terraform Validation Suite ===

Validating labs/01-automation-runbook-ec2-provisioning/infrastructure/terraform... OK
Validating labs/02-patch-manager-compliance-baseline/infrastructure/terraform... OK
Validating labs/03-session-manager-bastion-replacement/infrastructure/terraform... OK
Validating labs/04-parameter-store-event-driven-config/infrastructure/terraform... OK
Validating labs/05-inventory-resource-data-sync/infrastructure/terraform... OK
Validating labs/06-fleet-manager-node-management/infrastructure/terraform... OK
Validating labs/07-bedrock-session-log-analysis/infrastructure/terraform... OK
Validating shared/modules/ssm-instance-profile... OK
Validating shared/modules/ssm-vpc... OK

All checks passed
```

> **Note:** Each `terraform init` downloads the AWS provider, so the first run requires internet access and takes a minute or two.

---

## Shared Modules

Reusable Terraform modules consumed by all labs via relative paths:

| Module | Purpose |
|--------|---------|
| [`ssm-vpc`](shared/modules/ssm-vpc/) | VPC with public/private subnets, optional NAT gateway, and optional VPC endpoints for SSM (ssm, ssmmessages, ec2messages) |
| [`ssm-instance-profile`](shared/modules/ssm-instance-profile/) | IAM role + instance profile with `AmazonSSMManagedInstanceCore`, supporting additional policy attachments |

See each module's README for usage examples and input/output documentation.

---

## Comparative Analysis

See [`COMPARISON.md`](COMPARISON.md) for a structured comparison of SSM capabilities — Automation, Patch Manager, Session Manager, Run Command, Parameter Store, Inventory, and Fleet Manager — with decision matrices, cost analysis, and trade-off discussion based on hands-on implementation across all labs.

---

## Directory Structure

```
aws-fleet-operations-labs/
  README.md
  COMPARISON.md
  CLAUDE.md
  LICENSE
  .gitignore
  .devcontainer/devcontainer.json
  .github/
    dependabot.yml
    workflows/terraform-ci.yml       # Layer 2: CI/CD pipeline
  tests/validate.sh                  # Local validation script
  docs/
  shared/
    modules/
      ssm-vpc/                       # VPC with NAT + optional SSM endpoints
      ssm-instance-profile/          # IAM role + instance profile
    policies/
      ec2-assume-role.json           # EC2 service trust policy
      ssm-assume-role.json           # SSM service trust policy
  labs/
    01-automation-runbook-ec2-provisioning/
    02-patch-manager-compliance-baseline/
    03-session-manager-bastion-replacement/
    04-parameter-store-event-driven-config/
    05-inventory-resource-data-sync/
    06-fleet-manager-node-management/
    07-bedrock-session-log-analysis/
```

---

## Cost Awareness

SSM labs are costlier than simple Config labs due to VPC infrastructure and EC2 instances:

| Component | Estimated Monthly Cost | Used By |
|-----------|----------------------:|---------|
| NAT Gateway | ~$32 | Labs 01, 02, 04, 05 |
| VPC Endpoints (3x SSM) | ~$21.60 | Lab 03 |
| EC2 t2.micro (Linux) | ~$7.50 per instance | Labs 01-06 |
| EC2 t3.micro (Windows) | ~$12 | Lab 05 |
| S3 storage (logs) | ~$0.10 | Labs 02, 03, 05, 07 |
| CloudWatch Logs | ~$0.50 | Labs 03, 06 |
| Bedrock invocations | ~$0.01-0.10 per analysis | Lab 07 |
| Lambda | ~$0.01 | Lab 07 |
| CloudWatch Dashboard | Free (up to 3) | All labs |
| EventBridge rules | Free | All labs |
| SNS notifications | Free tier | All labs |

Estimated cost per lab: **$5-55/month** depending on architecture. See each lab's README for specific breakdown.

**Always run `terraform destroy` when done** to avoid ongoing charges from NAT gateways, VPC endpoints, and EC2 instances.

---

## Enhancement Roadmap

This collection follows the [5-Layer Enhancement Model](CLAUDE.md#5-layer-enhancement-model):

| Layer | Status |
|-------|--------|
| 1. Infrastructure as Code (Terraform) | Done — all labs |
| 2. CI/CD Pipeline (GitHub Actions) | Done — terraform fmt/validate on push and PR |
| 3. Monitoring & Observability (CloudWatch) | Done — dashboards, EventBridge rules, SNS notifications |
| 4. Finance Domain Twist (PCI-DSS patching, SOX compliance) | Planned |
| 5. Multi-Cloud Extension (Azure Automation / Update Manager) | Planned |

### What Layer 3 (Monitoring) Adds

Every lab includes an operational monitoring stack: EventBridge rules detect SSM state changes in real time, SNS delivers email notifications, and a CloudWatch dashboard visualizes event metrics for operational visibility.

**Why it matters per lab:**

- **Lab 01** (Automation Runbook) — EventBridge captures every automation execution status change. Instead of polling the console, the dashboard shows execution frequency and the SNS topic alerts on failures.
- **Lab 02** (Patch Manager) — Compliance state changes trigger EventBridge events. The dashboard tracks how often patches change compliance status across the fleet, surfacing drift patterns.
- **Lab 03** (Session Manager) — CloudTrail-based EventBridge rules detect session start/stop events. The dashboard correlates session activity with CloudWatch log volume, showing access patterns and anomalies.
- **Lab 04** (Parameter Store) — Two EventBridge rules capture parameter changes and policy actions (expiration warnings, no-change alerts). The dashboard visualizes configuration change frequency and policy trigger rates.
- **Lab 05** (Inventory) — EventBridge detects inventory resource state changes. The dashboard tracks collection success rates and notification volume across the heterogeneous fleet.
- **Lab 06** (Fleet Manager) — CloudWatch Agent publishes custom metrics (CPU, memory, disk, network) to a 6-widget fleet performance dashboard. EventBridge captures Run Command status changes via native SSM events.
- **Lab 07** (Bedrock Analysis) — Lambda pipeline metrics (invocations, errors, duration, percentiles) are visualized in a 4-widget dashboard. S3 PUT events trigger AI-powered session analysis with results published to SNS.

Layer 3 is what separates a learning exercise from a production-ready implementation. It demonstrates that infrastructure is not just deployed but actively **monitored** — operational events are captured, violations trigger alerts, and fleet health is tracked.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
