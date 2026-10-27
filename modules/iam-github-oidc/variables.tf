variable "role_name" {
  description = "Name of the IAM role assumed by GitHub Actions."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name must be 1-64 characters valid in an IAM role name."
  }
}

variable "create_oidc_provider" {
  description = "Create the account-wide GitHub OIDC identity provider. Set to false when another stack already owns it and pass oidc_provider_arn instead."
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of an existing token.actions.githubusercontent.com OIDC provider. Required when create_oidc_provider is false."
  type        = string
  default     = null

  validation {
    condition     = var.oidc_provider_arn == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "oidc_provider_arn must be the ARN of the token.actions.githubusercontent.com provider."
  }
}

variable "subjects" {
  description = <<-EOT
    OIDC `sub` claims allowed to assume the role, for example
    `repo:my-org/my-repo:ref:refs/heads/main` or `repo:my-org/my-repo:environment:prod`.
    Each entry must pin an organisation and repository; a trailing `*` is only
    allowed after the repository part.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0
    error_message = "At least one subject is required; an empty list would trust every repository."
  }

  validation {
    condition = alltrue([
      for s in var.subjects : can(regex("^repo:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+:(ref:refs/(heads|tags)/[A-Za-z0-9_./*-]+|environment:[A-Za-z0-9_.-]+|pull_request)$", s))
    ])
    error_message = "Each subject must look like repo:<org>/<repo>:ref:refs/heads/<branch>, repo:<org>/<repo>:ref:refs/tags/<tag>, repo:<org>/<repo>:environment:<name> or repo:<org>/<repo>:pull_request. Wildcards in org or repo are not allowed."
  }
}

variable "policy_statements" {
  description = "Inline policy statements granted to the role. Every statement must name explicit actions; `*` and service-wide wildcards such as `iam:*` are rejected."
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))

  validation {
    condition     = length(var.policy_statements) > 0
    error_message = "Provide at least one policy statement."
  }

  validation {
    condition = alltrue(flatten([
      for st in var.policy_statements : [for a in st.actions : a != "*" && !endswith(a, ":*")]
    ]))
    error_message = "Actions must be explicit: `*` and `<service>:*` are not allowed."
  }

  validation {
    condition = alltrue(flatten([
      for st in var.policy_statements : [for a in st.actions : !contains(["iam:createuser", "iam:createaccesskey", "iam:attachuserpolicy", "iam:putuserpolicy"], lower(a))]
    ]))
    error_message = "The CI role must not be able to mint long-lived IAM users or access keys."
  }
}

variable "max_session_duration" {
  description = "Maximum session length in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 900 and 43200 seconds."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional permissions boundary attached to the role."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
