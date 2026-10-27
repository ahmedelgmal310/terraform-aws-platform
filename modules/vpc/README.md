# vpc

Three-tier VPC spread across availability zones:

| Tier    | Route to the internet                     | Intended for                          |
|---------|-------------------------------------------|---------------------------------------|
| public  | Internet gateway                          | Load balancers, NAT gateways          |
| private | NAT gateway (`none`, `single` or `per_az`) | ECS tasks, anything that needs egress |
| intra   | None                                      | Databases and other data stores       |

Security defaults:

- The default security group is stripped of all rules.
- Public subnets do not auto-assign public IPs.
- VPC flow logs (ALL traffic by default) go to a CloudWatch Logs group encrypted with a dedicated, rotating KMS key. The flow log IAM role is scoped to that one log group and to the current account (`aws:SourceAccount`).
- Subnet CIDRs are derived deterministically with `cidrsubnet`, so the layout is predictable and reviewable in a plan.

## Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name             = "platform-prod"
  cidr_block       = "10.30.0.0/16"
  azs              = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  nat_gateway_mode = "per_az"

  flow_log_retention_days = 365
}
```

See [`examples/complete`](examples/complete).

## Tests

- `tests/unit`: mocked provider, assertions on the subnet layout, NAT modes, flow logs and every input validation.
- `tests/integration`: applied against LocalStack in CI, read back through the EC2 API, then destroyed.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| aws | >= 6.0, < 7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 6.0, < 7.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_default_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_security_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_kms_alias.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.private_nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route_table.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| azs | Availability zones to spread subnets across. One public, one private and one intra subnet is created per AZ. | `list(string)` | n/a | yes |
| cidr\_block | IPv4 CIDR block of the VPC. Must be a private (RFC 1918) range between /16 and /24. | `string` | n/a | yes |
| name | Name prefix applied to every resource in the VPC (for example `acme-dev`). | `string` | n/a | yes |
| enable\_flow\_logs | Ship VPC flow logs to an encrypted CloudWatch Logs group. | `bool` | `true` | no |
| flow\_log\_kms\_key\_arn | ARN of an existing KMS key used to encrypt the flow log group. When null a dedicated key with rotation is created. | `string` | `null` | no |
| flow\_log\_retention\_days | Retention of the flow log group in days. Must be a value CloudWatch Logs accepts. | `number` | `90` | no |
| flow\_log\_traffic\_type | Traffic captured by the flow log: ACCEPT, REJECT or ALL. | `string` | `"ALL"` | no |
| nat\_gateway\_mode | Egress for private subnets: `none` (no NAT), `single` (one shared NAT gateway, cheaper) or `per_az` (one NAT gateway per AZ, highly available). | `string` | `"single"` | no |
| subnet\_newbits | Number of bits added to the VPC prefix for every subnet (a /16 VPC with 4 newbits yields /20 subnets). | `number` | `4` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| azs | Availability zones used by the subnets, in subnet order. |
| flow\_log\_group\_name | CloudWatch Logs group receiving flow logs, or null when disabled. |
| flow\_log\_id | ID of the VPC flow log, or null when disabled. |
| intra\_subnet\_cidrs | CIDR blocks of the intra subnets. |
| intra\_subnet\_ids | IDs of the intra subnets (no internet route), one per AZ. |
| nat\_gateway\_ids | IDs of the NAT gateways (empty when nat\_gateway\_mode is none). |
| nat\_public\_ips | Elastic IPs attached to the NAT gateways, useful for allow-listing egress. |
| private\_route\_table\_ids | IDs of the per-AZ private route tables. |
| private\_subnet\_cidrs | CIDR blocks of the private subnets. |
| private\_subnet\_ids | IDs of the private subnets (NAT egress), one per AZ. |
| public\_subnet\_cidrs | CIDR blocks of the public subnets. |
| public\_subnet\_ids | IDs of the public subnets, one per AZ. |
| vpc\_cidr\_block | IPv4 CIDR block of the VPC. |
| vpc\_id | ID of the VPC. |
<!-- END_TF_DOCS -->
