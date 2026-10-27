mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:123456789012:key/00000000-0000-0000-0000-000000000000" }
  }
}

variables {
  bucket_name = "unit-test-secure-bucket"
}

run "secure_defaults" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled with BucketOwnerEnforced."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Default encryption must be SSE-KMS."
  }

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating KMS key must be created when none is supplied."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must default to false."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) == 0
    error_message = "Access logging is opt-in."
  }
}

run "policy_enforces_tls" {
  command = plan

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && try(s.Condition.Bool["aws:SecureTransport"], "") == "false"
    ])
    error_message = "Bucket policy must deny requests without TLS."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Deny" && try(s.Condition.NumericLessThan["s3:TlsVersion"], "") == "1.2"
    ])
    error_message = "Bucket policy must deny TLS versions below 1.2."
  }

  assert {
    condition = contains(
      jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Resource,
      "arn:aws:s3:::unit-test-secure-bucket/*"
    )
    error_message = "TLS statement must cover objects in the bucket."
  }
}

run "existing_kms_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0
    error_message = "No key must be created when one is supplied."
  }

  assert {
    condition     = output.kms_key_arn == var.kms_key_arn
    error_message = "Supplied key must be used."
  }
}

run "access_logging_and_extra_statements" {
  command = plan

  variables {
    access_log_bucket = "unit-test-log-bucket"
    additional_policy_statements = [{
      Sid       = "AllowReadFromRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::123456789012:role/reader" }
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::unit-test-secure-bucket/*"
    }]
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_prefix == "s3/unit-test-secure-bucket/"
    error_message = "Default access log prefix is derived from the bucket name."
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 4
    error_message = "Extra statements are appended to the three mandatory ones."
  }
}

run "log_destination_bucket" {
  command = plan

  variables {
    accept_access_logs = true
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Sid == "AllowS3ServerAccessLogDelivery" && s.Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    ])
    error_message = "Log destination buckets must allow S3 log delivery scoped to this account."
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    bucket_name = "Invalid_Bucket"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_ip_like_name" {
  command = plan

  variables {
    bucket_name = "192.168.1.1"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_short_deletion_window" {
  command = plan

  variables {
    kms_key_deletion_window_days = 3
  }

  expect_failures = [var.kms_key_deletion_window_days]
}
