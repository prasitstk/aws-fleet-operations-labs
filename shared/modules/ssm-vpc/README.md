# ssm-vpc

Reusable Terraform module for a VPC configured for AWS Systems Manager connectivity.

## Features

- VPC with configurable CIDR block
- Public and private subnets across availability zones
- Optional NAT gateway for internet access from private subnets
- Optional VPC endpoints for SSM (ssm, ssmmessages, ec2messages) for bastion-free architectures
- Security groups for VPC endpoint access and managed instances

## Usage

```hcl
module "ssm_vpc" {
  source = "../../../../shared/modules/ssm-vpc"

  project_name        = "my-ssm-lab"
  vpc_cidr            = "10.0.0.0/16"
  enable_nat_gateway  = true   # Set false when using VPC endpoints
  enable_ssm_endpoints = false # Set true for bastion-free access

  common_tags = local.common_tags
}
```

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `project_name` | Project name used for resource naming and tagging | `string` | — | yes |
| `vpc_cidr` | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |
| `public_subnet_cidr` | CIDR block for the public subnet | `string` | `"10.0.1.0/24"` | no |
| `private_subnet_cidr` | CIDR block for the private subnet | `string` | `"10.0.2.0/24"` | no |
| `enable_nat_gateway` | Whether to create a NAT gateway for private subnet internet access | `bool` | `true` | no |
| `enable_ssm_endpoints` | Whether to create VPC endpoints for SSM (ssm, ssmmessages, ec2messages) | `bool` | `false` | no |
| `common_tags` | Tags to apply to all resources created by this module | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | ID of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `public_subnet_id` | ID of the public subnet |
| `private_subnet_id` | ID of the private subnet |
| `igw_id` | ID of the internet gateway |
| `nat_gw_id` | ID of the NAT gateway (null if disabled) |
| `instance_sg_id` | ID of the instance security group |
| `public_rt_id` | ID of the public route table |
| `private_rt_id` | ID of the private route table |
