# Data at rest must be encrypted, with customer-managed keys that rotate.
package terraform.encryption

import data.terraform.lib

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	lib.after(db).storage_encrypted != true
	msg := sprintf("%s: RDS storage must be encrypted", [db.address])
}

deny contains msg if {
	some db in lib.changes_of("aws_db_instance")
	not has_value_or_unknown(db, "kms_key_id")
	msg := sprintf("%s: RDS must use a customer-managed KMS key (kms_key_id)", [db.address])
}

deny contains msg if {
	some key in lib.changes_of("aws_kms_key")
	lib.after(key).enable_key_rotation != true
	msg := sprintf("%s: KMS key rotation must be enabled", [key.address])
}

deny contains msg if {
	some lg in lib.changes_of("aws_cloudwatch_log_group")
	not has_value_or_unknown(lg, "kms_key_id")
	msg := sprintf("%s: CloudWatch log group must be encrypted with KMS", [lg.address])
}

deny contains msg if {
	some table in lib.changes_of("aws_dynamodb_table")
	not dynamodb_encrypted(table)
	msg := sprintf("%s: DynamoDB table must use server-side encryption with a KMS key", [table.address])
}

deny contains msg if {
	some vol in lib.changes_of("aws_ebs_volume")
	lib.after(vol).encrypted != true
	msg := sprintf("%s: EBS volume must be encrypted", [vol.address])
}

has_value_or_unknown(rc, attr) if {
	value := lib.after(rc)[attr]
	value != null
	value != ""
}

has_value_or_unknown(rc, attr) if lib.unknown(rc, attr)

dynamodb_encrypted(table) if {
	some sse in lib.after(table).server_side_encryption
	sse.enabled == true
}
