# S3 buckets must never be public, must be KMS-encrypted and versioned, and
# must refuse plaintext transport.
package terraform.s3

import data.terraform.lib

public_acls := {"public-read", "public-read-write", "authenticated-read"}

pab_flags := ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"]

deny contains msg if {
	some bucket in lib.changes_of("aws_s3_bucket")
	not has_full_public_access_block(bucket)
	msg := sprintf("%s: S3 bucket has no public access block with all four settings enabled in the same module", [bucket.address])
}

deny contains msg if {
	some pab in lib.changes_of("aws_s3_bucket_public_access_block")
	some flag in pab_flags
	lib.after(pab)[flag] != true
	msg := sprintf("%s: %s must be true", [pab.address, flag])
}

deny contains msg if {
	some acl in lib.changes_of("aws_s3_bucket_acl")
	lib.after(acl).acl in public_acls
	msg := sprintf("%s: public canned ACL %q is not allowed", [acl.address, lib.after(acl).acl])
}

deny contains msg if {
	some bucket in lib.changes_of("aws_s3_bucket")
	not has_kms_encryption(bucket)
	msg := sprintf("%s: S3 bucket must use SSE-KMS default encryption", [bucket.address])
}

deny contains msg if {
	some bucket in lib.changes_of("aws_s3_bucket")
	not has_versioning(bucket)
	msg := sprintf("%s: S3 bucket must have versioning enabled", [bucket.address])
}

deny contains msg if {
	some policy in lib.changes_of("aws_s3_bucket_policy")
	doc := lib.policy_doc(policy, "policy")
	not denies_insecure_transport(doc)
	msg := sprintf("%s: bucket policy must deny requests where aws:SecureTransport is false", [policy.address])
}

deny contains msg if {
	some policy in lib.changes_of("aws_s3_bucket_policy")
	doc := lib.policy_doc(policy, "policy")
	some st in lib.as_array(doc.Statement)
	st.Effect == "Allow"
	principal_is_public(st.Principal)
	not st.Condition
	msg := sprintf("%s: bucket policy statement %q grants access to everyone", [policy.address, object.get(st, "Sid", "")])
}

has_full_public_access_block(bucket) if {
	some pab in lib.changes_of("aws_s3_bucket_public_access_block")
	lib.module_of(pab) == lib.module_of(bucket)
	every flag in pab_flags {
		lib.after(pab)[flag] == true
	}
}

has_kms_encryption(bucket) if {
	some sse in lib.changes_of("aws_s3_bucket_server_side_encryption_configuration")
	lib.module_of(sse) == lib.module_of(bucket)
	some rule in lib.after(sse).rule
	some def in rule.apply_server_side_encryption_by_default
	def.sse_algorithm in {"aws:kms", "aws:kms:dsse"}
}

has_versioning(bucket) if {
	some v in lib.changes_of("aws_s3_bucket_versioning")
	lib.module_of(v) == lib.module_of(bucket)
	some cfg in lib.after(v).versioning_configuration
	cfg.status == "Enabled"
}

denies_insecure_transport(doc) if {
	some st in lib.as_array(doc.Statement)
	st.Effect == "Deny"
	lower(sprintf("%v", [st.Condition.Bool["aws:SecureTransport"]])) == "false"
}

principal_is_public("*")

principal_is_public(p) if p.AWS == "*"

principal_is_public(p) if "*" in p.AWS
