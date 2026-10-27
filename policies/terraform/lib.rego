# Helpers shared by the plan policies. Input is `terraform show -json <plan>`.
package terraform.lib

# Managed resources that the plan creates or updates.
changes contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

changes_of(type) := {rc | some rc in changes; rc.type == type}

after(rc) := rc.change.after

# True when the attribute will only be known after apply.
unknown(rc, attr) if rc.change.after_unknown[attr] == true

# Module path of a resource ("" for the root module). Resources created by
# the same module instance are paired through it, for example a bucket and
# its public access block.
module_of(rc) := object.get(rc, "module_address", "")

# Environment tag merged from provider default_tags.
environment(rc) := rc.change.after.tags_all.Environment

# Policy documents are JSON strings in the plan; unknown ones are skipped.
policy_doc(rc, attr) := json.unmarshal(rc.change.after[attr]) if is_string(rc.change.after[attr])

as_array(x) := x if is_array(x)

as_array(x) := [x] if not is_array(x)

# Null-safe list access: absent or null attributes become an empty list.
list_or_empty(x) := x if is_array(x)

list_or_empty(x) := [] if not is_array(x)
