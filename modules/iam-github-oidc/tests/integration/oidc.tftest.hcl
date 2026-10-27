# Integration test against LocalStack: creates the OIDC provider and role,
# reads the role back through the IAM API, then destroys everything.

provider "aws" {
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

variables {
  role_name = "it-gha-deploy"
  subjects  = ["repo:ahmedelgmal310/terraform-aws-platform:environment:dev"]
  policy_statements = [{
    sid       = "ReadPlatformBuckets"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::it-platform-data", "arn:aws:s3:::it-platform-data/*"]
  }]
}

run "apply_role" {
  command = apply

  assert {
    condition     = endswith(output.role_arn, ":role/it-gha-deploy")
    error_message = "Role was not created."
  }

  assert {
    condition     = endswith(output.oidc_provider_arn, ":oidc-provider/token.actions.githubusercontent.com")
    error_message = "OIDC provider ARN is wrong."
  }
}

run "read_back_from_api" {
  command = apply

  module {
    source = "./tests/integration/verify"
  }

  variables {
    role_name = run.apply_role.role_name
  }

  assert {
    condition     = length(output.trusted_subjects) == 1 && output.trusted_subjects[0] == "repo:ahmedelgmal310/terraform-aws-platform:environment:dev"
    error_message = "Trust policy read from IAM does not restrict the subject claim."
  }

  assert {
    condition     = length(output.provider_client_ids) == 1 && output.provider_client_ids[0] == "sts.amazonaws.com"
    error_message = "OIDC provider read from IAM does not have the STS audience."
  }
}
