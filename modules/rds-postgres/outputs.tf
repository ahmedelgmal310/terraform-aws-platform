output "db_instance_identifier" {
  description = "Identifier of the instance."
  value       = aws_db_instance.this.identifier
}

output "db_instance_arn" {
  description = "ARN of the instance."
  value       = aws_db_instance.this.arn
}

output "db_instance_resource_id" {
  description = "Resource ID, used in `rds-db:connect` IAM policies for IAM database authentication."
  value       = aws_db_instance.this.resource_id
}

output "endpoint" {
  description = "Connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Security group attached to the instance; reference it from client security groups."
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS-managed master password."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "kms_key_arn" {
  description = "KMS key encrypting storage, Performance Insights and the master secret."
  value       = local.kms_key_arn
}
