# iam-github-oidc

An IAM role that GitHub Actions assumes through OIDC, so CI never holds long-lived AWS keys.

- Creates the `token.actions.githubusercontent.com` identity provider, or reuses an existing one (the provider is account-wide).
- The trust policy pins `aud` to `sts.amazonaws.com` and restricts `sub` to the exact repositories, branches, tags or GitHub environments you list. Validation rejects wildcards in the organisation or repository part (`repo:org/*`, `repo:*`).
- Permissions are passed as a list of statements and rendered into one inline policy. Validation rejects `*`, `<service>:*`, and actions that create IAM users or access keys.
- Sessions default to one hour; an optional permissions boundary can be attached.

## Usage

```hcl
module "deploy_role" {
  source = "../../modules/iam-github-oidc"

  role_name = "platform-prod-github-deploy"
  subjects  = ["repo:my-org/my-repo:environment:prod"]

  policy_statements = [{
    sid       = "RollService"
    actions   = ["ecs:UpdateService", "ecs:DescribeServices"]
    resources = ["arn:aws:ecs:eu-west-1:111111111111:service/platform-prod-app/platform-prod-app"]
  }]
}
```

In the workflow, grant `id-token: write` and pass the role ARN to `aws-actions/configure-aws-credentials` (pinned to a commit SHA) as `role-to-assume`.

## Tests

- `tests/unit`: mocked provider; asserts the trust conditions, policy rendering and every guard rail.
- `tests/integration`: applied against LocalStack in CI; the role and the OIDC provider are read back through the IAM API.

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
| [aws_iam_openid_connect_provider.github](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| policy\_statements | Inline policy statements granted to the role. Every statement must name explicit actions; `*` and service-wide wildcards such as `iam:*` are rejected. | ```list(object({ sid = string actions = list(string) resources = list(string) conditions = optional(list(object({ test = string variable = string values = list(string) })), []) }))``` | n/a | yes |
| role\_name | Name of the IAM role assumed by GitHub Actions. | `string` | n/a | yes |
| subjects | OIDC `sub` claims allowed to assume the role, for example `repo:my-org/my-repo:ref:refs/heads/main` or `repo:my-org/my-repo:environment:prod`. Each entry must pin an organisation and repository; a trailing `*` is only allowed after the repository part. | `list(string)` | n/a | yes |
| create\_oidc\_provider | Create the account-wide GitHub OIDC identity provider. Set to false when another stack already owns it and pass oidc\_provider\_arn instead. | `bool` | `true` | no |
| max\_session\_duration | Maximum session length in seconds. | `number` | `3600` | no |
| oidc\_provider\_arn | ARN of an existing token.actions.githubusercontent.com OIDC provider. Required when create\_oidc\_provider is false. | `string` | `null` | no |
| permissions\_boundary\_arn | Optional permissions boundary attached to the role. | `string` | `null` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| oidc\_provider\_arn | ARN of the GitHub OIDC provider trusted by the role. |
| permissions\_policy\_json | Rendered inline permissions policy. |
| role\_arn | ARN of the role to put in `aws-actions/configure-aws-credentials` (`role-to-assume`). |
| role\_name | Name of the role. |
| trust\_policy\_json | Rendered trust (assume role) policy. |
<!-- END_TF_DOCS -->
