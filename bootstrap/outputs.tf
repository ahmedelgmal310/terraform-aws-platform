output "state_bucket" {
  description = "Name of the state bucket (backend `bucket`)."
  value       = module.state_bucket.bucket_id
}

output "lock_table" {
  description = "Name of the DynamoDB lock table (backend `dynamodb_table`)."
  value       = aws_dynamodb_table.lock.name
}

output "kms_key_arn" {
  description = "KMS key protecting state at rest (backend `kms_key_id`)."
  value       = module.state_bucket.kms_key_arn
}

output "backend_config" {
  description = "Ready-to-use partial backend configuration for live/<env>/backend.hcl."
  value       = <<-EOT
    bucket         = "${module.state_bucket.bucket_id}"
    region         = "${var.region}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    encrypt        = true
    kms_key_id     = "${module.state_bucket.kms_key_arn}"
  EOT
}
