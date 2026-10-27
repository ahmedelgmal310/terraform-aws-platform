# s3-secure-bucket

An S3 bucket with the controls that should never be optional:

- All four S3 Block Public Access settings on, and ACLs disabled (`BucketOwnerEnforced`).
- Default SSE-KMS with S3 Bucket Keys, using a dedicated rotating key unless one is supplied.
- Versioning always on; noncurrent versions expire and incomplete multipart uploads are aborted.
- A bucket policy that denies non-TLS requests, TLS below 1.2, and uploads that ask for a non-KMS encryption header. Extra statements can be appended; the mandatory ones cannot be removed.
- Optional server access logging to another bucket. `accept_access_logs = true` turns a bucket into a log destination by allowing the S3 logging service to write to it for the current account only.

The bucket policy is built from the bucket name rather than from resource attributes, so it is fully known at plan time and can be checked by the OPA policies in [`policies/`](../../policies).

## Usage

```hcl
module "logs" {
  source             = "../../modules/s3-secure-bucket"
  bucket_name        = "acme-prod-access-logs-111111111111"
  accept_access_logs = true
}

module "artifacts" {
  source            = "../../modules/s3-secure-bucket"
  bucket_name       = "acme-prod-artifacts-111111111111"
  access_log_bucket = module.logs.bucket_id
}
```

See [`examples/complete`](examples/complete).

## Tests

- `tests/unit`: mocked provider; asserts public access block, ownership, versioning, SSE-KMS, policy statements and input validation.
- `tests/integration`: applied against LocalStack in CI (a log bucket plus a data bucket logging into it); the bucket policy is read back through the S3 API.

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
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Globally unique bucket name. | `string` | n/a | yes |
| abort\_incomplete\_multipart\_days | Days after which incomplete multipart uploads are aborted. | `number` | `7` | no |
| accept\_access\_logs | Mark this bucket as an S3 server access log destination: grants the S3 logging service write access for sources in this account. | `bool` | `false` | no |
| access\_log\_bucket | Name of a bucket that receives server access logs. Null disables access logging (use for the log bucket itself). | `string` | `null` | no |
| access\_log\_prefix | Key prefix for server access logs. | `string` | `null` | no |
| additional\_policy\_statements | Extra IAM policy statements (already decoded objects) merged into the bucket policy after the mandatory TLS and encryption statements. | `list(any)` | `[]` | no |
| force\_destroy | Allow Terraform to delete the bucket even when it still contains objects. Keep false outside of ephemeral environments. | `bool` | `false` | no |
| kms\_key\_arn | ARN of an existing KMS key for SSE-KMS. When null a dedicated key with rotation is created. | `string` | `null` | no |
| kms\_key\_deletion\_window\_days | Waiting period before a module-created KMS key is deleted. | `number` | `30` | no |
| noncurrent\_version\_expiration\_days | Days after which noncurrent object versions are permanently deleted. | `number` | `90` | no |
| tags | Tags added to every resource. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | ARN of the bucket. |
| bucket\_id | Name of the bucket. |
| bucket\_regional\_domain\_name | Regional domain name of the bucket. |
| kms\_key\_arn | ARN of the KMS key used for default encryption. |
| policy\_json | Rendered bucket policy. |
<!-- END_TF_DOCS -->
