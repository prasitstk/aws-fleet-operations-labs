# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Public collection repo for AWS Systems Manager fleet operations labs. Each lab is built from scratch using AWS documentation as reference, with Terraform as the IaC baseline. The collection tells a progressive fleet operations story: provision, patch, access, configure, inventory, monitor, and analyze with AI.

## Terraform Commands

Each lab has Terraform under `labs/NN-name/infrastructure/terraform/`.

```bash
cd labs/01-automation-runbook-ec2-provisioning/infrastructure/terraform

terraform init          # First time or after provider changes
terraform plan          # Preview
terraform apply         # Deploy
terraform destroy       # Always tear down after testing to avoid charges
```

A `terraform.tfvars.example` is provided in each lab. Copy to `terraform.tfvars` and customize before applying. The `.gitignore` excludes `*.tfvars` (but keeps `*.tfvars.example`) and `*.zip` (Lambda deployment packages).

## Architecture

### Shared Modules

Labs consume reusable modules via relative paths (e.g., `source = "../../../../shared/modules/ssm-vpc"`):

- **`shared/modules/ssm-vpc/`** — VPC with public/private subnets, optional NAT gateway, and optional VPC endpoints for SSM (ssm, ssmmessages, ec2messages). Use `enable_nat_gateway` for labs needing internet in private subnets. Use `enable_ssm_endpoints` for bastion-free architectures (Lab 03).
- **`shared/modules/ssm-instance-profile/`** — IAM role + instance profile with `AmazonSSMManagedInstanceCore` managed policy attached via `aws_iam_role_policy_attachment`. Accepts `additional_policy_arns` for lab-specific permissions (e.g., `AmazonSSMPatchAssociation` for Lab 02). Uses `aws_iam_role_policy_attachment` (not deprecated `managed_policy_arns`).
- **`shared/policies/`** — JSON trust policy templates for EC2 and SSM service assume-role.

### Lab Structure Pattern

```
labs/NN-topic-name/
  README.md
  architecture.drawio          # Source diagram (draw.io XML)
  architecture.png             # Exported at 2x scale
  infrastructure/terraform/    # main.tf, variables.tf, outputs.tf, versions.tf
  src/                         # Scripts, runbook YAML, Lambda code (when needed)
```

All labs use the same provider constraints: Terraform `>= 1.5`, AWS provider `>= 5.0`. Default region is `us-east-1`.

### 5-Layer Enhancement Model

1. **IaC** — Terraform baseline (all labs)
2. **CI/CD** — GitHub Actions (all labs)
3. **Monitoring** — CloudWatch dashboards, EventBridge rules, SNS notifications (all labs)
4. **Finance Domain** — Financial data integration (SOX patch compliance, PCI-DSS hardening)
5. **Multi-Cloud** — AWS + Azure side-by-side (Azure Automation / Update Management)

### Lab Status

| Lab | Status | Layers |
|-----|--------|--------|
| 01 — Automation Runbook EC2 Provisioning | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 02 — Patch Manager Compliance Baseline | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 03 — Session Manager Bastion Replacement | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 04 — Parameter Store Event-Driven Config | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 05 — Inventory Resource Data Sync | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 06 — Fleet Manager Node Management | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |
| 07 — Bedrock Session Log Analysis | Complete | 1 (IaC), 2 (CI/CD), 3 (Monitoring) |

## Layer 3 Design: EventBridge Metrics Approach

Labs 01-05 use native `AWS/Events` and `AWS/SNS` CloudWatch metrics from existing EventBridge rules and SNS topics for their dashboards. This avoids adding Lambda metrics publishers — the EventBridge `MatchedEvents`, `Invocations`, and `FailedInvocations` metrics are free and automatically available. Lab 03 additionally uses `AWS/Logs` `IncomingLogEvents` from its CloudWatch log group. Labs 06-07 have their own custom metrics (CloudWatch Agent for Lab 06, Lambda metrics for Lab 07).

## Bedrock-Specific Gotchas (Lab 07)

- **Model access:** First-time Anthropic model users may need to submit use case details before access is granted.
- **Region availability:** Bedrock is available in `us-east-1` (matches default region).
- **Per-invocation cost:** ~$0.01-0.10 depending on input/output tokens. Uses Claude Haiku 4.5 cross-region inference profile (`us.anthropic.claude-haiku-4-5-20251001-v1:0`).
- **Lambda timeout:** Bedrock invocations can take 5-30 seconds. Lambda timeout is set to at least 60 seconds.
- **IAM permissions:** Lambda needs `bedrock:InvokeModel` for the model ARN plus `bedrock:GetInferenceProfile`.

## SSM-Specific Gotchas

- **SSM Agent connectivity:** Instances need either internet access (NAT gateway) or VPC endpoints to reach SSM service endpoints.
- **Instance profile propagation:** Allow 1-2 minutes after attaching an instance profile for SSM Agent to register.
- **Session Manager logging:** Session logs to S3/CloudWatch require instance role write permissions to those destinations.
- **Patch baselines:** Custom baselines override defaults only when associated with a patch group. Tag instances with `Patch Group` (case-sensitive).
- **Windows instance registration:** Windows instances take 5-10 minutes to register with SSM (vs. 1-2 minutes for Linux).
- **Resource Data Sync bucket policy:** Requires `ssm.amazonaws.com` to `GetBucketAcl` and `PutObject` with `s3:x-amz-acl = bucket-owner-full-control` condition.

## AWS Provider v6 Gotchas

The `>= 5.0` constraint resolves to AWS provider v6.x:

- `managed_policy_arns` on `aws_iam_role` is deprecated — use `aws_iam_role_policy_attachment` instead.
- `data.aws_region.current.name` is deprecated — use `.id` instead.
- Always validate resource schemas against the installed provider version (v6.x), not older docs.

## Architecture Diagrams

Labs use draw.io (`.drawio` XML with `mxgraph.aws4.*` stencils). Export workflow:

```bash
/Applications/draw.io.app/Contents/MacOS/draw.io --export --format png --scale 2 --border 10 -b white -o architecture.png architecture.drawio
```

**Note:** Use `-b white` (short flag) for background. The long form `--background` is misinterpreted as an input path.

Commit both `.drawio` and `.png`. The README references the PNG.

Use **direct shape** style for AWS icons (`sketch=0;...shape=mxgraph.aws4.{service};`), not the legacy `resourceIcon` wrapper.

## Conventions

- Lab directories: `NN-descriptive-topic-name` (kebab-case)
- Tags: every resource gets `local.common_tags` (`Project`, `Environment`, `ManagedBy`)
- Git commits: Conventional Commits format — `type(scope): description`
