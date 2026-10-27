# IAM must be least-privilege and GitHub OIDC trust must be pinned.
package terraform.iam

import data.terraform.lib

policy_attrs := {
	"aws_iam_policy": "policy",
	"aws_iam_role_policy": "policy",
	"aws_iam_user_policy": "policy",
	"aws_iam_group_policy": "policy",
}

admin_policies := {"AdministratorAccess", "IAMFullAccess", "PowerUserAccess"}

github_host := "token.actions.githubusercontent.com"

allow_statements contains [rc.address, st] if {
	some type, attr in policy_attrs
	some rc in lib.changes_of(type)
	doc := lib.policy_doc(rc, attr)
	some st in lib.as_array(doc.Statement)
	st.Effect == "Allow"
}

deny contains msg if {
	some [address, st] in allow_statements
	some action in lib.as_array(st.Action)
	wildcard_action(action)
	msg := sprintf("%s: statement %q allows wildcard action %q", [address, object.get(st, "Sid", ""), action])
}

deny contains msg if {
	some [address, st] in allow_statements
	st.NotAction
	msg := sprintf("%s: statement %q uses NotAction with Allow", [address, object.get(st, "Sid", "")])
}

deny contains msg if {
	some [address, st] in allow_statements
	some action in lib.as_array(st.Action)
	lower(action) == "iam:passrole"
	"*" in lib.as_array(st.Resource)
	msg := sprintf("%s: iam:PassRole must be scoped to specific roles", [address])
}

deny contains msg if {
	some type in {"aws_iam_role_policy_attachment", "aws_iam_policy_attachment", "aws_iam_user_policy_attachment", "aws_iam_group_policy_attachment"}
	some rc in lib.changes_of(type)
	some name in admin_policies
	endswith(lib.after(rc).policy_arn, concat("", [":policy/", name]))
	msg := sprintf("%s: attaching %s is not allowed", [rc.address, name])
}

deny contains msg if {
	some user in lib.changes_of("aws_iam_access_key")
	msg := sprintf("%s: long-lived IAM access keys are not allowed; use OIDC or roles", [user.address])
}

deny contains msg if {
	some role in lib.changes_of("aws_iam_role")
	doc := lib.policy_doc(role, "assume_role_policy")
	some st in lib.as_array(doc.Statement)
	trusts_github(st)
	not pins_claim(st, "aud")
	msg := sprintf("%s: GitHub OIDC trust must pin the aud claim to sts.amazonaws.com", [role.address])
}

deny contains msg if {
	some role in lib.changes_of("aws_iam_role")
	doc := lib.policy_doc(role, "assume_role_policy")
	some st in lib.as_array(doc.Statement)
	trusts_github(st)
	not pins_claim(st, "sub")
	msg := sprintf("%s: GitHub OIDC trust must restrict the sub claim", [role.address])
}

deny contains msg if {
	some role in lib.changes_of("aws_iam_role")
	doc := lib.policy_doc(role, "assume_role_policy")
	some st in lib.as_array(doc.Statement)
	trusts_github(st)
	some op in ["StringLike", "StringEquals"]
	some sub in lib.as_array(object.get(st.Condition, [op, concat(":", [github_host, "sub"])], []))
	broad_subject(sub)
	msg := sprintf("%s: GitHub OIDC subject %q is too broad", [role.address, sub])
}

wildcard_action("*")

wildcard_action(action) if endswith(action, ":*")

trusts_github(st) if {
	st.Effect == "Allow"
	endswith(st.Principal.Federated, concat("/", ["oidc-provider", github_host]))
}

pins_claim(st, claim) if {
	some op in ["StringLike", "StringEquals"]
	st.Condition[op][concat(":", [github_host, claim])]
}

# repo:org/* or repo:* would let any repository (or any repository of the
# organisation) assume the role.
broad_subject(sub) if not regex.match(`^repo:[^*/]+/[^*/:]+:.+$`, sub)
