package terraform.encryption_test

import data.terraform.encryption

rc(type, after, unknown) := {
	"address": concat(".", [type, "this"]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after, "after_unknown": unknown},
}

test_encrypted_rds_with_pending_key_passes if {
	db := rc("aws_db_instance", {"storage_encrypted": true}, {"kms_key_id": true})
	count(encryption.deny) == 0 with input as {"resource_changes": [db]}
}

test_unencrypted_rds_denied if {
	db := rc("aws_db_instance", {"storage_encrypted": false, "kms_key_id": "arn:aws:kms:eu-west-1:1:key/x"}, {})
	some msg in encryption.deny with input as {"resource_changes": [db]}
	contains(msg, "RDS storage must be encrypted")
}

test_rds_with_aws_managed_key_denied if {
	db := rc("aws_db_instance", {"storage_encrypted": true, "kms_key_id": null}, {})
	some msg in encryption.deny with input as {"resource_changes": [db]}
	contains(msg, "customer-managed KMS key")
}

test_kms_without_rotation_denied if {
	key := rc("aws_kms_key", {"enable_key_rotation": false}, {})
	some msg in encryption.deny with input as {"resource_changes": [key]}
	contains(msg, "rotation")
}

test_plain_log_group_denied if {
	lg := rc("aws_cloudwatch_log_group", {"name": "x", "kms_key_id": null}, {})
	some msg in encryption.deny with input as {"resource_changes": [lg]}
	contains(msg, "log group")
}

test_log_group_with_pending_key_passes if {
	lg := rc("aws_cloudwatch_log_group", {"name": "x"}, {"kms_key_id": true})
	count(encryption.deny) == 0 with input as {"resource_changes": [lg]}
}

test_dynamodb_without_sse_denied if {
	table := rc("aws_dynamodb_table", {"server_side_encryption": []}, {})
	some msg in encryption.deny with input as {"resource_changes": [table]}
	contains(msg, "DynamoDB")
}

test_dynamodb_with_sse_passes if {
	table := rc("aws_dynamodb_table", {"server_side_encryption": [{"enabled": true}]}, {})
	count(encryption.deny) == 0 with input as {"resource_changes": [table]}
}

test_unencrypted_ebs_denied if {
	vol := rc("aws_ebs_volume", {"encrypted": false}, {})
	some msg in encryption.deny with input as {"resource_changes": [vol]}
	contains(msg, "EBS")
}
