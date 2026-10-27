# Every taggable resource must carry the cost-allocation and ownership tags.
package terraform.tags

import data.terraform.lib

required_tags := {"Project", "Environment", "Owner", "ManagedBy"}

allowed_environments := {"dev", "staging", "prod", "shared"}

deny contains msg if {
	some rc in lib.changes
	tags := lib.after(rc).tags_all
	is_object(tags)
	missing := required_tags - {k | some k, _ in tags}
	count(missing) > 0
	msg := sprintf("%s: missing required tags %v", [rc.address, sort(missing)])
}

deny contains msg if {
	some rc in lib.changes
	env := lib.after(rc).tags_all.Environment
	not env in allowed_environments
	msg := sprintf("%s: Environment tag %q is not one of %v", [rc.address, env, sort(allowed_environments)])
}

deny contains msg if {
	some rc in lib.changes
	lib.after(rc).tags_all.ManagedBy != "terraform"
	msg := sprintf("%s: ManagedBy tag must be \"terraform\"", [rc.address])
}
