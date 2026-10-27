# rds-postgres

PostgreSQL on RDS with:

- Storage, Performance Insights and the master secret encrypted with a customer-managed, rotating KMS key.
- Master password created and stored by RDS in Secrets Manager (`manage_master_user_password`), so it never appears in Terraform state or variables.
- IAM database authentication enabled.
- `rds.force_ssl = 1`, connection, DDL and slow-query logging, and log export to CloudWatch.
- Never publicly accessible. A dedicated security group allows 5432 only from the security groups or private CIDRs you list (`0.0.0.0/0` is rejected by validation) and has no egress.
- Automated backups that cannot be turned off (1 to 35 days), deletion protection and a final snapshot by default.

## Usage

```hcl
module "db" {
  source = "../../modules/rds-postgres"

  identifier                 = "platform-prod-db"
  instance_class             = "db.r7g.large"
  multi_az                   = true
  backup_retention_days      = 35
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.intra_subnet_ids
  allowed_security_groups    = { app = module.app.security_group_id }
}
```

See [`examples/complete`](examples/complete).

## Tests

RDS is not part of LocalStack Community, so this module is **not applied in CI**. It is covered by:

- `tests/unit`: mocked provider; asserts encryption, the TLS parameter, IAM auth, network scoping, backup and deletion settings, and input validation.
- The `plan` job, which plans it inside every environment and runs the OPA policies on the result.

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
| [aws_db_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidrs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_groups](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| identifier | RDS instance identifier; also used as a name prefix for the subnet group, parameter group and security group. | `string` | n/a | yes |
| instance\_class | Instance class, for example `db.t4g.micro` or `db.r7g.large`. | `string` | n/a | yes |
| subnet\_ids | Subnets for the DB subnet group. Use intra or private subnets; at least two AZs are required. | `list(string)` | n/a | yes |
| vpc\_id | VPC that hosts the database security group. | `string` | n/a | yes |
| allocated\_storage | Initial storage in GiB. | `number` | `20` | no |
| allowed\_cidr\_blocks | CIDR blocks allowed to connect on the PostgreSQL port. Must be private ranges. | `list(string)` | `[]` | no |
| allowed\_security\_groups | Security groups allowed to connect on the PostgreSQL port, keyed by a static name (for example `app`) so the keys are known at plan time even when the IDs are not. | `map(string)` | `{}` | no |
| apply\_immediately | Apply modifications immediately instead of during the maintenance window. | `bool` | `false` | no |
| backup\_retention\_days | Automated backup retention in days. | `number` | `7` | no |
| backup\_window | Daily backup window (UTC), hh24:mi-hh24:mi. | `string` | `"02:00-03:00"` | no |
| db\_name | Name of the initial database. | `string` | `"app"` | no |
| deletion\_protection | Block deletion of the instance through the API. | `bool` | `true` | no |
| engine\_version | PostgreSQL major or major.minor version, for example `17` or `17.6`. | `string` | `"17"` | no |
| kms\_key\_arn | KMS key for storage, Performance Insights and the managed master secret. When null a dedicated key with rotation is created. | `string` | `null` | no |
| maintenance\_window | Weekly maintenance window (UTC), ddd:hh24:mi-ddd:hh24:mi. | `string` | `"sun:03:30-sun:04:30"` | no |
| master\_username | Master user name. The password is created and rotated by RDS in Secrets Manager; it never appears in Terraform state. | `string` | `"platform_admin"` | no |
| max\_allocated\_storage | Upper limit for storage autoscaling in GiB. Set equal to allocated\_storage to disable autoscaling. | `number` | `100` | no |
| monitoring\_interval | Enhanced Monitoring interval in seconds (0 disables it). | `number` | `60` | no |
| multi\_az | Run a synchronous standby in a second AZ. | `bool` | `false` | no |
| performance\_insights\_enabled | Enable Performance Insights (encrypted with the module KMS key). | `bool` | `true` | no |
| performance\_insights\_retention\_days | Performance Insights retention: 7 (free tier) or a multiple of 31 up to 731. | `number` | `7` | no |
| skip\_final\_snapshot | Skip the final snapshot on deletion. Only for throwaway environments. | `bool` | `false` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| address | Hostname of the instance. |
| db\_instance\_arn | ARN of the instance. |
| db\_instance\_identifier | Identifier of the instance. |
| db\_instance\_resource\_id | Resource ID, used in `rds-db:connect` IAM policies for IAM database authentication. |
| endpoint | Connection endpoint (host:port). |
| kms\_key\_arn | KMS key encrypting storage, Performance Insights and the master secret. |
| master\_user\_secret\_arn | ARN of the Secrets Manager secret holding the RDS-managed master password. |
| port | PostgreSQL port. |
| security\_group\_id | Security group attached to the instance; reference it from client security groups. |
<!-- END_TF_DOCS -->
