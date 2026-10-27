# ecs-fargate

An ECS cluster running one Fargate service. ECS was chosen over EKS because it is the smaller and cheaper control plane for a handful of services. Neither ECS nor EKS is available in LocalStack Community, so this module is verified with mocked unit tests and environment plans, not with an apply.

What it sets up:

- A cluster with Container Insights. ECS Exec is disabled on the service; the cluster-level exec configuration is still encrypted and logged in case someone turns it on.
- `FARGATE` capacity, or `FARGATE_SPOT` with one on-demand base task (`use_fargate_spot`).
- A task definition with a read-only root filesystem, all Linux capabilities dropped, and an init process. Validation requires an image tag or digest and rejects `:latest`.
- Secrets injected from Secrets Manager or SSM (`valueFrom`); plain values in `secrets` are rejected.
- Separate execution and task roles, both trusted only by `ecs-tasks.amazonaws.com` in the current account. The execution role can write to its own log group, read the listed secrets and pull from the listed ECR repositories, and nothing else. The task role starts with no permissions.
- Tasks in private subnets without public IPs. Ingress only from the security groups you list; egress limited to HTTPS plus explicit rules (for example PostgreSQL to the database security group).
- A deployment circuit breaker with rollback, and CPU target-tracking autoscaling.

## Usage

```hcl
module "app" {
  source = "../../modules/ecs-fargate"

  name            = "platform-prod-app"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  container_image = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/app:1.4.2"
  cpu             = 1024
  memory          = 2048
  min_capacity    = 3
  max_capacity    = 10

  ecr_repository_arns = ["arn:aws:ecr:eu-west-1:111111111111:repository/app"]
}
```

See [`examples/complete`](examples/complete).

## Tests

- `tests/unit`: mocked provider; asserts the container hardening, secret injection, network isolation, IAM scoping, capacity strategy, autoscaling bounds and input validation.
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
| [aws_appautoscaling_policy.cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_kms_alias.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| container\_image | Container image, pinned by tag or digest. `latest` and untagged images are rejected. | `string` | n/a | yes |
| name | Name of the cluster and service (for example `acme-dev-api`). | `string` | n/a | yes |
| subnet\_ids | Private subnets the tasks run in. Tasks never get a public IP. | `list(string)` | n/a | yes |
| vpc\_id | VPC of the service security group. | `string` | n/a | yes |
| allowed\_ingress\_security\_groups | Security groups (for example a load balancer) allowed to reach the container port, keyed by a static name so the keys are known at plan time. | `map(string)` | `{}` | no |
| container\_port | Port the container listens on. | `number` | `8080` | no |
| cpu | Task CPU units (256, 512, 1024, 2048, 4096, 8192 or 16384). | `number` | `256` | no |
| cpu\_architecture | CPU architecture of the image: ARM64 (Graviton, cheaper) or X86\_64. | `string` | `"ARM64"` | no |
| cpu\_target\_utilization | Average CPU utilisation (percent) that target tracking aims for. | `number` | `60` | no |
| desired\_count | Initial number of tasks. Autoscaling owns the value afterwards. | `number` | `1` | no |
| ecr\_repository\_arns | Private ECR repositories the task execution role may pull from. Leave empty for public images. | `list(string)` | `[]` | no |
| egress\_rules | Additional egress to security groups inside the VPC, such as a database, keyed by a static name. HTTPS egress to the internet (image pulls, AWS APIs) is always allowed. | ```map(object({ description = string port = number security_group_id = string }))``` | `{}` | no |
| environment | Plain-text environment variables for the container. Do not put secrets here; use `secrets`. | `map(string)` | `{}` | no |
| kms\_key\_arn | KMS key used for the log group. When null a dedicated key with rotation is created. | `string` | `null` | no |
| log\_retention\_days | Retention of the container log group in days. | `number` | `30` | no |
| max\_capacity | Maximum number of tasks autoscaling may run. | `number` | `2` | no |
| memory | Task memory in MiB. Must be a valid Fargate combination for the chosen CPU. | `number` | `512` | no |
| min\_capacity | Minimum number of tasks kept by autoscaling. | `number` | `1` | no |
| secrets | Map of environment variable name to Secrets Manager secret ARN (or SSM parameter ARN) injected at start-up. | `map(string)` | `{}` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |
| use\_fargate\_spot | Prefer FARGATE\_SPOT capacity (keeps one on-demand task as a base). Suitable for non-production. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | ARN of the ECS cluster. |
| cluster\_name | Name of the ECS cluster. |
| execution\_role\_arn | ARN of the task execution role. |
| log\_group\_name | CloudWatch Logs group of the containers. |
| security\_group\_id | Security group of the tasks; allow it on downstream resources such as the database. |
| service\_name | Name of the ECS service. |
| task\_definition\_arn | ARN of the current task definition revision. |
| task\_role\_arn | ARN of the application role. |
| task\_role\_name | Name of the application role; attach workload permissions to it. |
<!-- END_TF_DOCS -->
