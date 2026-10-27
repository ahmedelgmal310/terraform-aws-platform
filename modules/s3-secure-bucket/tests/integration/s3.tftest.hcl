# Integration test against LocalStack: creates a log bucket and a data bucket
# that ships access logs to it, reads the configuration back through the S3
# API, then destroys both.

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
}

run "log_bucket" {
  command   = apply
  state_key = "log_bucket"

  variables {
    bucket_name        = "it-platform-access-logs"
    force_destroy      = true
    accept_access_logs = true
  }

  assert {
    condition     = output.bucket_id == "it-platform-access-logs"
    error_message = "Log bucket was not created."
  }
}

run "data_bucket" {
  command   = apply
  state_key = "data_bucket"

  variables {
    bucket_name       = "it-platform-data"
    force_destroy     = true
    access_log_bucket = run.log_bucket.bucket_id
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::it-platform-data"
    error_message = "Unexpected bucket ARN."
  }

  assert {
    condition     = startswith(output.kms_key_arn, "arn:aws:kms:us-east-1:")
    error_message = "A KMS key must have been created."
  }
}

run "read_back_from_api" {
  command = apply

  module {
    source = "./tests/integration/verify"
  }

  variables {
    bucket = run.data_bucket.bucket_id
  }

  assert {
    condition     = output.policy_has_tls_deny
    error_message = "Bucket policy read from S3 does not deny insecure transport."
  }

  assert {
    condition     = output.policy_statement_count == 3
    error_message = "Bucket policy read from S3 does not contain the three mandatory statements."
  }
}
