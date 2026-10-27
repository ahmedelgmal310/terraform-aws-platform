package terraform.tags_test

import data.terraform.tags

rc(tags_all) := {
	"address": "aws_vpc.this",
	"mode": "managed",
	"type": "aws_vpc",
	"change": {"actions": ["create"], "after": {"tags_all": tags_all}, "after_unknown": {}},
}

good := {"Project": "platform", "Environment": "dev", "Owner": "platform-team", "ManagedBy": "terraform"}

test_complete_tags_pass if {
	count(tags.deny) == 0 with input as {"resource_changes": [rc(good)]}
}

test_missing_owner_denied if {
	some msg in tags.deny with input as {"resource_changes": [rc(object.remove(good, ["Owner"]))]}
	contains(msg, "Owner")
}

test_unknown_environment_denied if {
	some msg in tags.deny with input as {"resource_changes": [rc(object.union(good, {"Environment": "qa"}))]}
	contains(msg, "is not one of")
}

test_wrong_managed_by_denied if {
	some msg in tags.deny with input as {"resource_changes": [rc(object.union(good, {"ManagedBy": "console"}))]}
	contains(msg, "ManagedBy")
}

test_untaggable_resource_ignored if {
	route := {
		"address": "aws_route.this",
		"mode": "managed",
		"type": "aws_route",
		"change": {"actions": ["create"], "after": {"destination_cidr_block": "0.0.0.0/0"}, "after_unknown": {}},
	}
	count(tags.deny) == 0 with input as {"resource_changes": [route]}
}

test_data_sources_ignored if {
	ds := object.union(rc({}), {"mode": "data"})
	count(tags.deny) == 0 with input as {"resource_changes": [ds]}
}
