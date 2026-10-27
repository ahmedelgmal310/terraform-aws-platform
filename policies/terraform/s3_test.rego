package terraform.s3_test

import data.terraform.s3

rc(type, address, module, after) := {
	"address": address,
	"module_address": module,
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": {}},
}

secure_bucket(module) := [
	rc("aws_s3_bucket", concat(".", [module, "aws_s3_bucket.this"]), module, {"bucket": "b"}),
	rc("aws_s3_bucket_public_access_block", concat(".", [module, "aws_s3_bucket_public_access_block.this"]), module, {
		"block_public_acls": true, "block_public_policy": true,
		"ignore_public_acls": true, "restrict_public_buckets": true,
	}),
	rc("aws_s3_bucket_server_side_encryption_configuration", concat(".", [module, "aws_s3_bucket_server_side_encryption_configuration.this"]), module, {"rule": [{"apply_server_side_encryption_by_default": [{"sse_algorithm": "aws:kms"}]}]}),
	rc("aws_s3_bucket_versioning", concat(".", [module, "aws_s3_bucket_versioning.this"]), module, {"versioning_configuration": [{"status": "Enabled"}]}),
	rc("aws_s3_bucket_policy", concat(".", [module, "aws_s3_bucket_policy.this"]), module, {"policy": json.marshal({"Statement": [{
		"Effect": "Deny", "Principal": "*", "Action": "s3:*",
		"Condition": {"Bool": {"aws:SecureTransport": "false"}},
	}]})}),
]

# Replaces one attribute on resources of the given type, leaves others as-is.
patched(r, type, path, value) := json.patch(r, [{"op": "replace", "path": path, "value": value}]) if r.type == type

patched(r, type, _, _) := r if r.type != type

test_secure_bucket_passes if {
	count(s3.deny) == 0 with input as {"resource_changes": secure_bucket("module.data")}
}

test_missing_public_access_block_denied if {
	changes := [r | some r in secure_bucket("module.data"); r.type != "aws_s3_bucket_public_access_block"]
	some msg in s3.deny with input as {"resource_changes": changes}
	contains(msg, "no public access block")
}

test_public_access_block_in_other_module_does_not_count if {
	bucket := [r | some r in secure_bucket("module.a"); r.type != "aws_s3_bucket_public_access_block"]
	other := [r | some r in secure_bucket("module.b"); r.type == "aws_s3_bucket_public_access_block"]
	some msg in s3.deny with input as {"resource_changes": array.concat(bucket, other)}
	contains(msg, "module.a.aws_s3_bucket.this")
}

test_partial_public_access_block_denied if {
	changes := [r |
		some orig in secure_bucket("module.data")
		r := json.patch(orig, [{"op": "replace", "path": "/change/after/restrict_public_buckets", "value": false}])
		orig.type == "aws_s3_bucket_public_access_block"
	]
	some msg in s3.deny with input as {"resource_changes": changes}
	contains(msg, "restrict_public_buckets must be true")
}

test_public_acl_denied if {
	acl := rc("aws_s3_bucket_acl", "aws_s3_bucket_acl.this", "", {"acl": "public-read"})
	some msg in s3.deny with input as {"resource_changes": [acl]}
	contains(msg, "public canned ACL")
}

test_sse_s3_denied if {
	changes := [patched(r, "aws_s3_bucket_server_side_encryption_configuration", "/change/after/rule/0/apply_server_side_encryption_by_default/0/sse_algorithm", "AES256") | some r in secure_bucket("")]
	some msg in s3.deny with input as {"resource_changes": changes}
	contains(msg, "SSE-KMS")
}

test_suspended_versioning_denied if {
	changes := [patched(r, "aws_s3_bucket_versioning", "/change/after/versioning_configuration/0/status", "Suspended") | some r in secure_bucket("")]
	some msg in s3.deny with input as {"resource_changes": changes}
	contains(msg, "versioning")
}

test_policy_without_tls_deny_denied if {
	policy := rc("aws_s3_bucket_policy", "aws_s3_bucket_policy.this", "", {"policy": json.marshal({"Statement": [{"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::123456789012:root"}, "Action": "s3:GetObject"}]})})
	some msg in s3.deny with input as {"resource_changes": [policy]}
	contains(msg, "aws:SecureTransport")
}

test_public_principal_denied if {
	policy := rc("aws_s3_bucket_policy", "aws_s3_bucket_policy.this", "", {"policy": json.marshal({"Statement": [
		{"Effect": "Deny", "Principal": "*", "Action": "s3:*", "Condition": {"Bool": {"aws:SecureTransport": "false"}}},
		{"Sid": "Public", "Effect": "Allow", "Principal": "*", "Action": "s3:GetObject"},
	]})})
	some msg in s3.deny with input as {"resource_changes": [policy]}
	contains(msg, "grants access to everyone")
}

test_deleted_bucket_ignored if {
	deleted := json.patch(rc("aws_s3_bucket", "aws_s3_bucket.old", "", {}), [{"op": "replace", "path": "/change/actions", "value": ["delete"]}])
	count(s3.deny) == 0 with input as {"resource_changes": [deleted]}
}
