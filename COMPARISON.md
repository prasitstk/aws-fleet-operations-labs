# AWS Systems Manager Capabilities — Comparative Analysis

A structured comparison of AWS Systems Manager features to inform architecture decisions for fleet operations and instance management.

---

## Comparison Dimensions

| Dimension | SSM Automation | Patch Manager | Session Manager | Run Command | Parameter Store | Inventory | Fleet Manager |
|---|---|---|---|---|---|---|---|
| **Primary use case** | Multi-step workflow orchestration across AWS services | Automated OS/software patching with compliance tracking | Bastion-free interactive shell access to private instances | Ad-hoc script execution on managed instances | Centralized config & secrets management | Fleet-wide asset discovery and software audit | Unified operations console aggregating SSM features |
| **Setup complexity** | Medium (YAML document + automation role + target resources) | Medium (baseline + group + maintenance window + task) | Medium (VPC endpoints + session document + KMS + logging) | Low (instance profile + SSM document) | Low (parameters + optional KMS key) | Low (association + optional Resource Data Sync + S3) | Low (instance profile + SSM Agent connectivity) |
| **IAM requirements** | Dedicated automation assume role (ec2:RunInstances, ssm:SendCommand, iam:PassRole), instance profile | AmazonSSMManagedInstanceCore on instances, SSM service role for maintenance window tasks | AmazonSSMManagedInstanceCore, operator needs ssm:StartSession, instance role needs logs/S3/KMS write | AmazonSSMManagedInstanceCore on instances, caller needs ssm:SendCommand | ssm:GetParameter*, kms:Decrypt for SecureString | AmazonSSMManagedInstanceCore, ssm:PutInventory for custom types, S3 write for data sync | AmazonSSMManagedInstanceCore + CloudWatch Agent policy for enhanced monitoring |
| **Network requirements** | SSM Agent needs internet or VPC endpoints | SSM Agent needs internet or VPC endpoints | VPC endpoints (ssm, ssmmessages, ec2messages) — no internet required; additional endpoints for logs, KMS, S3 | SSM Agent needs internet or VPC endpoints | SSM Agent needs internet or VPC endpoints | SSM Agent needs internet or VPC endpoints | SSM Agent needs internet or VPC endpoints; public subnet + IGW simplest |
| **Logging & audit** | Execution history (365 days), CloudWatch Logs from Run Command steps, CloudTrail | S3 output from RunPatchBaseline, EventBridge compliance state changes, CloudTrail | Dual-destination: CloudWatch Logs (real-time transcript) + S3 (post-session archive), CloudTrail for session lifecycle | Command invocation history, optional S3 output, CloudTrail | EventBridge for change events, CloudTrail for API calls | Resource Data Sync to S3 (JsonSerDe), EventBridge inventory state changes, CloudTrail | CloudWatch metrics/logs via agent, native EventBridge Run Command events |
| **Scheduling support** | On-demand (CLI/API); can be triggered by EventBridge or Step Functions | Maintenance windows (cron/rate expressions), on-demand scan/install via Run Command | On-demand (operator-initiated); EventBridge detects session lifecycle events | Direct invocation or via maintenance windows (cron/rate) | Parameter policies (Expiration, NoChangeNotification) | State Manager associations with rate/cron expressions (min 30 minutes) | On-demand via console or CLI; delegates to underlying features for scheduling |
| **Multi-account support** | Cross-account role assumption for automation execution | AWS Organizations patch policies, delegated administrator | Cross-account role assumption; centralized session logs in logging account | Cross-account via SendCommand with delegated roles | Cross-account sharing via RAM or resource policies | Resource Data Sync supports cross-account S3 targets | Multi-account via AWS Organizations delegated administrator |
| **Cost model** | Free (SSM), but launched resources (EC2, NAT) incur charges | Free (SSM), but EC2/NAT/S3 infrastructure costs apply | Free (SSM), but VPC endpoints (~$7.20/endpoint/month) + KMS key ($1/month) | Free (SSM), but EC2/NAT infrastructure costs apply | Standard: free, Advanced: $0.05/param/month | Free (SSM), but EC2/NAT/S3 infrastructure costs apply | Free (SSM console), CW Agent metrics ~$0.30/metric/month, CW Dashboard $3/month |
| **Integration points** | EC2, Run Command, IAM PassRole, EventBridge, Step Functions | EventBridge, SNS, S3, maintenance windows, State Manager, Run Command | VPC endpoints, KMS, CloudWatch Logs, S3, EventBridge, SNS, Parameter Store | Maintenance windows, Automation steps, S3 output, EventBridge | EventBridge, EC2 user_data, Lambda, ECS task defs | EventBridge, S3, Athena, State Manager, custom SSM documents | CloudWatch Agent, Run Command, Session Manager, Patch Manager, Inventory, EventBridge, SNS |

## When to Use What

### SSM Automation

**Best for:** Multi-step workflow orchestration that spans AWS services.

- Chains actions in a YAML runbook — launch EC2, wait for state transitions, execute commands — with inter-step output passing (`{{ StepName.OutputKey }}`)
- Lab 01 demonstrates a 4-step provisioning runbook: RunInstances, WaitForInstanceRunning, InstallApache, InstallNode
- Dedicated automation assume role enforces least-privilege (scoped `iam:PassRole` prevents escalation)
- Fully parameterized documents support reuse across environments without redeploying Terraform

**Choose Automation over Run Command** when you need orchestration, conditional logic, or cross-service actions (EC2 launch, RDS snapshots, Lambda invocations).

### Patch Manager

**Best for:** Automated fleet-wide OS patching with compliance enforcement.

- Custom patch baselines define approval rules per severity — Critical/Important auto-approve faster than Medium/Low
- Patch groups (tag-based) associate baselines with instance fleets
- Maintenance windows schedule recurring patching with concurrency/error thresholds
- On-demand scan via Run Command for ad-hoc compliance checks
- EventBridge integration enables real-time compliance alerting
- S3 output logging provides audit trail for patch execution results

### Session Manager

**Best for:** Secure interactive shell access to private instances without bastion hosts or SSH keys.

- Lab 03 demonstrates a completely sealed network — instances in a private subnet with zero internet access, reachable only through VPC endpoints
- IAM-native authentication — no key pairs to rotate
- Every session logged to CloudWatch (real-time transcript) and S3 (durable archive), both encrypted with a customer-managed KMS key
- EventBridge detects session lifecycle events (StartSession, TerminateSession) for real-time notifications
- Eliminates the public attack surface, SSH key management overhead, and audit gaps that bastion hosts introduce

### Run Command

**Best for:** Ad-hoc script execution on managed instances without orchestration overhead.

- Directly invokes SSM documents (`AWS-RunShellScript`, `AWS-RunPowerShellScript`, `AWS-RunPatchBaseline`) on targets by ID or tag
- Lab 02 uses it via maintenance window tasks for scheduled patching and via direct `send-command` for on-demand compliance scans
- Stateless — no step chaining, no output passing between actions

**Choose Run Command over Automation** for one-off tasks (install a package, check a log file, run a compliance scan) where orchestration is unnecessary.

### Parameter Store

**Best for:** Centralized application configuration and secrets management.

- Path-based hierarchy enables per-environment isolation
- SecureString with customer-managed KMS keys for sensitive values
- EventBridge integration enables event-driven reactions to configuration changes
- Advanced tier adds parameter policies for expiration tracking and drift detection

### Inventory

**Best for:** Fleet-wide asset discovery and software auditing across heterogeneous OS platforms.

- Collects built-in inventory types (applications, AWS components, network config, Windows updates, services, roles) on a schedule via State Manager associations
- Resource Data Sync exports to S3 in JsonSerDe format for Athena queries and long-term retention beyond the 30-day SSM rolling window
- Custom inventory types extend coverage to application-specific metadata via `aws ssm put-inventory`
- EventBridge integration detects inventory state changes for real-time fleet awareness

### Fleet Manager

**Best for:** Unified operational management console for fleet-wide node visibility and actions.

- Aggregates Run Command, Session Manager, Patch Manager, and Inventory into a single console view
- Lab 06 demonstrates deploying a financial metrics collector across a fleet using a custom SSM Command document with tag-based targeting (`Fleet=financial-monitoring`)
- CloudWatch Agent provides enhanced OS-level metrics (CPU, memory, disk, network) beyond default EC2 monitoring, configured centrally via SSM Parameter Store
- Run Command emits native `EC2 Command Status-change Notification` events — no CloudTrail trail required (unlike Session Manager events in Lab 03)
- Public subnet architecture with IGW keeps costs low (~$25/month) compared to VPC endpoint-based architectures (~$45/month)

**Choose Fleet Manager** as the operational entry point for day-to-day fleet management. Use individual SSM features (Automation, Patch Manager, etc.) when you need their specific capabilities beyond what Fleet Manager's console provides.

## Key Trade-offs

### Bastion vs Session Manager

| Aspect | SSH + Bastion | Session Manager |
|---|---|---|
| **Network exposure** | Public IP on bastion, port 22 open | No public IPs — access via IAM + VPC endpoints |
| **Authentication** | SSH key pairs (manual rotation, shared across team) | IAM-native (temporary STS tokens, per-operator identity) |
| **Audit trail** | Manual syslog config, often incomplete | Automatic CloudTrail + encrypted CloudWatch/S3 transcripts |
| **Operator identity** | Shared `ec2-user` — hard to trace who did what | IAM principal preserved in every log entry |
| **Estimated cost** | ~$40/month (bastion EC2 + NAT) | ~$45-50/month (VPC endpoints + KMS) |

Cost is comparable, but the hidden overhead of SSH key rotation, access troubleshooting, and incomplete audit logs tips the balance toward Session Manager for any team larger than one operator.

### NAT Gateway vs VPC Endpoints

| Aspect | NAT Gateway (Lab 01) | VPC Endpoints (Lab 03) |
|---|---|---|
| **Cost** | ~$32/month | ~$21.60/month (3 SSM endpoints) |
| **Internet access** | Full outbound (package repos, external APIs) | SSM-only (no internet egress) |
| **Security** | Traffic exits VPC to public internet | Traffic stays within AWS network |
| **Setup** | Single resource + route table entry | One endpoint per service + security group |

**Decision rule:** If instances need general internet access (package installs, external APIs), NAT is necessary regardless. If SSM is the only reason for outbound access, VPC endpoints are cheaper and more secure. Production architectures often use both — VPC endpoints for SSM plus a NAT for controlled internet access.

### Scheduled Patching vs On-Demand

| Aspect | Maintenance Windows | Direct `send-command` |
|---|---|---|
| **Trigger** | Cron/rate expression (recurring) | Manual CLI/API call (one-time) |
| **Controls** | Concurrency limits, error thresholds | None — runs on all targets immediately |
| **Best for** | Steady-state production patching | Ad-hoc compliance scans, emergency patches |

Both modes use the same patch baseline rules — the difference is trigger mechanism, not patch logic. Use scheduled windows for steady-state and on-demand for incident response or pre-deployment validation.

### Standard vs Advanced Tier (Parameter Store)

| Aspect | Standard | Advanced ($0.05/param/month) |
|---|---|---|
| **Limit** | 10,000 parameters | 100,000 parameters |
| **Types** | String, StringList, SecureString | Same |
| **Parameter policies** | Not available | Expiration, NoChangeNotification |
| **Best for** | Most use cases | Lifecycle-managed secrets |

**Practical guidance:** Use Standard by default. Promote individual parameters to Advanced only when you need policy-driven lifecycle management. Lab 04 demonstrates this with an Advanced-tier database password — the expiration policy triggers a notification 15 days before expiry, shifting rotation responsibility from operators to the system.

### Parameter Store vs Secrets Manager

| Aspect | Parameter Store SecureString | Secrets Manager |
|---|---|---|
| **Cost** | Free (Standard tier) | $0.40/secret/month + $0.05/10K API calls |
| **Rotation** | Manual or via CI/CD | Built-in Lambda rotation templates |
| **Integration** | EC2 user_data, SSM documents, path-based hierarchy | RDS/Redshift/DocumentDB native rotation |
| **Cross-account** | Via RAM or resource policies | Built-in cross-account sharing |
| **100 secrets at scale** | $0/month | $40/month |

**Choose Parameter Store** when rotation is handled externally (CI/CD, manual process). **Choose Secrets Manager** when you need built-in rotation schedules (e.g., database passwords rotating every 30 days without application changes).

### Fleet Manager — Unified Operations Console

Fleet Manager is not a standalone SSM feature — it's a unified console that aggregates Run Command, Session Manager, Patch Manager, and Inventory into a single pane of glass. It provides a centralized view of all managed nodes with quick access to operational actions.

**What Fleet Manager adds beyond individual features:**
- **Node summary view:** Instance health, SSM Agent status, platform, IP addresses, tags — all in one table
- **Performance counters:** Real-time CPU, memory, disk, network metrics per instance (no agent required, but limited to real-time only)
- **File system browser:** Navigate instance file systems through the console
- **OS user management:** View and manage OS-level users across the fleet
- **Run Command shortcuts:** Execute common operations directly from the node context menu

Lab 06 demonstrates Fleet Manager's operational management capabilities — deploying applications via Run Command at scale, collecting enhanced metrics with CloudWatch Agent, and building fleet-wide dashboards.

### CloudWatch Agent vs Fleet Manager Performance Counters

| Aspect | Fleet Manager Counters | CloudWatch Agent |
|---|---|---|
| **Setup** | Zero (built into SSM) | Install agent + configure via SSM Parameter |
| **Metrics** | CPU, memory, disk I/O, network (basic) | Fully customizable (hundreds of metrics) |
| **Historical data** | Real-time only (no retention) | Configurable retention (days to years) |
| **Dashboards** | Per-instance only in Fleet Manager console | CloudWatch Dashboards (fleet-wide aggregation) |
| **Alerts** | None | CloudWatch Alarms (threshold + anomaly detection) |
| **Cost** | Free | ~$0.30/custom metric/month |
| **Best for** | Quick spot-checks during troubleshooting | Production monitoring with historical trending |

**Practical guidance:** Use Fleet Manager's built-in performance counters for ad-hoc troubleshooting (e.g., "is this instance CPU-bound right now?"). Deploy CloudWatch Agent when you need historical data, fleet-wide aggregation, alerting, or custom application metrics. Lab 06 uses CloudWatch Agent because it needs persistent dashboards and log collection — capabilities that Fleet Manager's real-time counters cannot provide.

### Run Command Events (Native) vs Session Events (CloudTrail)

| Aspect | Run Command Events | Session Manager Events |
|---|---|---|
| **Event source** | Native SSM event | AWS API Call via CloudTrail |
| **Detail-type** | `EC2 Command Status-change Notification` | `AWS API Call via CloudTrail` |
| **CloudTrail required** | No | Yes (active trail must exist) |
| **Event triggers** | Command status changes (Pending, InProgress, Success, Failed) | StartSession, TerminateSession, ResumeSession API calls |
| **Lab** | Lab 06 | Lab 03 |

Run Command emits first-class EventBridge events — no CloudTrail trail needed. Session Manager events are only visible through CloudTrail, requiring an active trail with management event logging enabled. This is why Lab 06 needs no CloudTrail trail while Lab 03 must create one.

## AI-Powered Log Analysis with Bedrock (Lab 07)

### Bedrock + Session Manager Logs

**Best for:** Automated security and compliance analysis of SSM session transcripts.

- Consumes session logs generated by Lab 03 (CloudWatch Logs + S3 transcripts)
- Lambda reads session transcripts, sends to Bedrock for AI-powered analysis
- Identifies security risks: privilege escalation, credential access, destructive commands
- Generates compliance summaries aligned with organizational access policies
- EventBridge triggers analysis on new session log delivery

### When to Use AI Analysis vs Manual Review

| Aspect | Manual Session Log Review | Bedrock AI Analysis |
|---|---|---|
| **Scale** | Practical for <10 sessions/day | Scales to hundreds of sessions |
| **Consistency** | Varies by reviewer skill and attention | Consistent criteria applied to every session |
| **Speed** | Minutes to hours per session | Seconds per session |
| **Cost** | Analyst time | ~$0.01-0.10 per invocation |
| **Detection quality** | High for known patterns | Good for known + novel patterns |
| **Compliance** | Manual documentation | Automated compliance reports |

**Practical guidance:** Use Bedrock analysis as a first-pass filter — flag high-risk sessions for human review. Never rely solely on AI analysis for security-critical decisions.

## References

- [AWS Systems Manager Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html)
- [SSM Automation Runbook Reference](https://docs.aws.amazon.com/systems-manager-automation-runbooks/latest/userguide/automation-runbook-reference.html)
- [AWS Patch Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-patch.html)
- [AWS Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS Systems Manager Inventory](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-inventory.html)
- [Resource Data Sync](https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-inventory-datasync.html)
- [AWS Fleet Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/fleet.html)
- [AWS Systems Manager Pricing](https://aws.amazon.com/systems-manager/pricing/)
- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
- [Amazon Bedrock Pricing](https://aws.amazon.com/bedrock/pricing/)
