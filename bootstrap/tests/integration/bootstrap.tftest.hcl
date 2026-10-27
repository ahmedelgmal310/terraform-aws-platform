# Integration test against LocalStack: builds the state backend, then a
# second Terraform run reads it back through the S3 and DynamoDB APIs.

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
}

variables {
  project       = "it-platform"
  region        = "us-east-1"
  force_destroy = true
}

run "apply_backend" {
  command = apply

  assert {
    condition     = output.state_bucket == "it-platform-tfstate-000000000000"
    error_message = "State bucket name must embed the account ID."
  }

  assert {
    condition     = output.lock_table == "it-platform-tfstate-lock"
    error_message = "Lock table was not created."
  }

  assert {
    condition     = aws_dynamodb_table.lock.hash_key == "LockID"
    error_message = "Lock table must use LockID as its hash key, as the S3 backend expects."
  }
}

run "read_back_from_api" {
  command = apply

  module {
    source = "./tests/integration/verify"
  }

  variables {
    bucket = run.apply_backend.state_bucket
    table  = run.apply_backend.lock_table
  }

  assert {
    condition     = output.bucket_versioning == "Enabled"
    error_message = "State bucket versioning is not enabled."
  }

  assert {
    condition     = output.table_sse_enabled
    error_message = "Lock table is not encrypted."
  }
}
