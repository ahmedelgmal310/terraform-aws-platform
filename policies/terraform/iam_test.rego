package terraform.iam_test

import data.terraform.iam

rc(type, after) := {
	"address": concat(".", [type, "this"]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

role_policy(statements) := rc("aws_iam_role_policy", {"policy": json.marshal({"Version": "2012-10-17", "Statement": statements})})

github_role(condition) := rc("aws_iam_role", {"assume_role_policy": json.marshal({"Statement": [{
	"Effect": "Allow",
	"Action": "sts:AssumeRoleWithWebIdentity",
	"Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"},
	"Condition": condition,
}]})})

pinned := {
	"StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
	"StringLike": {"token.actions.githubusercontent.com:sub": ["repo:acme/infra:environment:prod"]},
}

test_scoped_policy_passes if {
	p := role_policy([{"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::b/*"}])
	count(iam.deny) == 0 with input as {"resource_changes": [p]}
}

test_star_action_denied if {
	p := role_policy([{"Sid": "Admin", "Effect": "Allow", "Action": "*", "Resource": "*"}])
	some msg in iam.deny with input as {"resource_changes": [p]}
	contains(msg, "wildcard action")
}

test_service_wildcard_denied if {
	p := role_policy([{"Effect": "Allow", "Action": ["s3:GetObject", "iam:*"], "Resource": "*"}])
	some msg in iam.deny with input as {"resource_changes": [p]}
	contains(msg, "iam:*")
}

test_wildcard_in_deny_statement_allowed if {
	p := role_policy([{"Effect": "Deny", "Action": "*", "Resource": "*", "Condition": {"Bool": {"aws:SecureTransport": "false"}}}])
	count(iam.deny) == 0 with input as {"resource_changes": [p]}
}

test_not_action_denied if {
	p := role_policy([{"Effect": "Allow", "NotAction": "iam:*", "Resource": "*"}])
	some msg in iam.deny with input as {"resource_changes": [p]}
	contains(msg, "NotAction")
}

test_passrole_star_denied if {
	p := role_policy([{"Effect": "Allow", "Action": "iam:PassRole", "Resource": "*"}])
	some msg in iam.deny with input as {"resource_changes": [p]}
	contains(msg, "PassRole")
}

test_admin_attachment_denied if {
	a := rc("aws_iam_role_policy_attachment", {"policy_arn": "arn:aws:iam::aws:policy/AdministratorAccess"})
	some msg in iam.deny with input as {"resource_changes": [a]}
	contains(msg, "AdministratorAccess")
}

test_access_key_denied if {
	some msg in iam.deny with input as {"resource_changes": [rc("aws_iam_access_key", {"user": "ci"})]}
	contains(msg, "access keys")
}

test_pinned_github_trust_passes if {
	count(iam.deny) == 0 with input as {"resource_changes": [github_role(pinned)]}
}

test_github_trust_without_sub_denied if {
	some msg in iam.deny with input as {"resource_changes": [github_role({"StringEquals": pinned.StringEquals})]}
	contains(msg, "sub claim")
}

test_github_trust_without_aud_denied if {
	some msg in iam.deny with input as {"resource_changes": [github_role({"StringLike": pinned.StringLike})]}
	contains(msg, "aud claim")
}

test_github_trust_org_wildcard_denied if {
	broad := object.union(pinned, {"StringLike": {"token.actions.githubusercontent.com:sub": "repo:acme/*"}})
	some msg in iam.deny with input as {"resource_changes": [github_role(broad)]}
	contains(msg, "too broad")
}

test_github_trust_any_repo_denied if {
	broad := object.union(pinned, {"StringLike": {"token.actions.githubusercontent.com:sub": "repo:*"}})
	some msg in iam.deny with input as {"resource_changes": [github_role(broad)]}
	contains(msg, "too broad")
}
