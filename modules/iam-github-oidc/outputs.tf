output "role_arn" {
  description = "ARN of the role to put in `aws-actions/configure-aws-credentials` (`role-to-assume`)."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "Name of the role."
  value       = aws_iam_role.this.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider trusted by the role."
  value       = local.oidc_provider_arn
}

output "trust_policy_json" {
  description = "Rendered trust (assume role) policy."
  value       = aws_iam_role.this.assume_role_policy
}

output "permissions_policy_json" {
  description = "Rendered inline permissions policy."
  value       = aws_iam_role_policy.this.policy
}
