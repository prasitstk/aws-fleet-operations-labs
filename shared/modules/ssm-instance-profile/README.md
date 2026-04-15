# ssm-instance-profile

Reusable Terraform module for an IAM role and instance profile with AWS Systems Manager connectivity.

## Features

- IAM role with EC2 trust policy
- `AmazonSSMManagedInstanceCore` managed policy attached via `aws_iam_role_policy_attachment`
- Support for additional policy ARNs (e.g., `AmazonSSMPatchAssociation`, CloudWatch Logs, S3 write)
- Instance profile ready for EC2 launch templates

## Usage

```hcl
module "ssm_instance_profile" {
  source = "../../../../shared/modules/ssm-instance-profile"

  project_name         = "my-ssm-lab"
  additional_policy_arns = [
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ]

  common_tags = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project_name` | Project name used for resource naming | `string` | — | yes |
| `role_name_suffix` | Suffix appended to the IAM role name | `string` | `"ssm-instance"` | no |
| `additional_policy_arns` | List of additional IAM policy ARNs to attach to the role | `list(string)` | `[]` | no |
| `common_tags` | Tags to apply to all resources created by this module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `role_name` | Name of the IAM role |
| `role_arn` | ARN of the IAM role |
| `instance_profile_name` | Name of the instance profile |
| `instance_profile_arn` | ARN of the instance profile |

## Design Decisions

- Uses `aws_iam_role_policy_attachment` instead of the deprecated `managed_policy_arns` attribute on `aws_iam_role` (AWS provider v6 compatibility).
- Trust policy loaded from shared JSON template at `shared/policies/ec2-assume-role.json`.
