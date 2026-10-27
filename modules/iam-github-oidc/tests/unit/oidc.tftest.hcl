mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  role_name = "gha-terraform-plan"
  subjects  = ["repo:acme/infra:ref:refs/heads/main", "repo:acme/infra:pull_request"]
  policy_statements = [
    {
      sid       = "ReadState"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = ["arn:aws:s3:::acme-tfstate", "arn:aws:s3:::acme-tfstate/*"]
    },
    {
      sid       = "DecryptState"
      actions   = ["kms:Decrypt"]
      resources = ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
      conditions = [
        { test = "StringEquals", variable = "kms:ViaService", values = ["s3.eu-west-1.amazonaws.com"] },
      ]
    },
  ]
}

run "trust_policy_is_scoped" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1
    error_message = "OIDC provider must be created by default."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Trust must point at the GitHub OIDC provider in this account."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "Audience must be pinned to sts.amazonaws.com."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringLike["token.actions.githubusercontent.com:sub"]) == toset(var.subjects)
    error_message = "Subject claim must be restricted to the configured subjects."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600
    error_message = "Sessions default to one hour."
  }
}

run "permissions_policy_rendering" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.this.policy).Statement) == 2
    error_message = "One IAM statement per input statement."
  }

  assert {
    condition     = !can(jsondecode(aws_iam_role_policy.this.policy).Statement[0].Condition)
    error_message = "Statements without conditions must not render an empty Condition block."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.this.policy).Statement[1].Condition.StringEquals["kms:ViaService"][0] == "s3.eu-west-1.amazonaws.com"
    error_message = "Conditions must be grouped by operator."
  }
}

run "existing_provider" {
  command = plan

  variables {
    create_oidc_provider = false
    oidc_provider_arn    = "arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "No provider must be created when an existing ARN is supplied."
  }

  assert {
    condition     = output.oidc_provider_arn == var.oidc_provider_arn
    error_message = "Trust must reference the supplied provider."
  }
}

run "rejects_provider_both_ways" {
  command = plan

  variables {
    oidc_provider_arn = "arn:aws:iam::210987654321:oidc-provider/token.actions.githubusercontent.com"
  }

  expect_failures = [aws_iam_openid_connect_provider.github]
}

run "rejects_missing_provider" {
  command = plan

  variables {
    create_oidc_provider = false
  }

  expect_failures = [aws_iam_role.this]
}

run "rejects_wildcard_repository" {
  command = plan

  variables {
    subjects = ["repo:acme/*"]
  }

  expect_failures = [var.subjects]
}

run "rejects_any_org" {
  command = plan

  variables {
    subjects = ["repo:*"]
  }

  expect_failures = [var.subjects]
}

run "rejects_empty_subjects" {
  command = plan

  variables {
    subjects = []
  }

  expect_failures = [var.subjects]
}

run "rejects_star_action" {
  command = plan

  variables {
    policy_statements = [{ sid = "Admin", actions = ["*"], resources = ["*"] }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_service_wildcard" {
  command = plan

  variables {
    policy_statements = [{ sid = "AllIam", actions = ["iam:*"], resources = ["*"] }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_access_key_creation" {
  command = plan

  variables {
    policy_statements = [{ sid = "Keys", actions = ["iam:CreateAccessKey"], resources = ["*"] }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_long_sessions" {
  command = plan

  variables {
    max_session_duration = 86400
  }

  expect_failures = [var.max_session_duration]
}
