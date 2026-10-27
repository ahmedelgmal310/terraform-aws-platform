data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  github_oidc_host = "token.actions.githubusercontent.com"

  # Constructed rather than read from the resource so the trust policy is
  # known at plan time and can be inspected by policy-as-code.
  oidc_provider_arn = coalesce(
    var.oidc_provider_arn,
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_host}"
  )

  trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOIDC"
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_provider_arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = var.subjects }
      }
    }]
  }

  permissions_policy = {
    Version = "2012-10-17"
    Statement = [
      for st in var.policy_statements : merge(
        {
          Sid      = st.sid
          Effect   = "Allow"
          Action   = st.actions
          Resource = st.resources
        },
        [
          for _ in range(length(st.conditions) > 0 ? 1 : 0) : {
            Condition = {
              for test in distinct([for c in st.conditions : c.test]) : test => {
                for c in st.conditions : c.variable => c.values if c.test == test
              }
            }
          }
        ]...
      )
    ]
  }

  tags = merge(var.tags, { "platform:module" = "iam-github-oidc" })
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.oidc_provider_arn == null
      error_message = "Set either create_oidc_provider = true or oidc_provider_arn, not both."
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Assumed by GitHub Actions via OIDC (${join(", ", var.subjects)})"
  assume_role_policy   = jsonencode(local.trust_policy)
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.create_oidc_provider || var.oidc_provider_arn != null
      error_message = "oidc_provider_arn is required when create_oidc_provider is false."
    }
  }

  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.role_name}-permissions"
  role   = aws_iam_role.this.id
  policy = jsonencode(local.permissions_policy)
}
