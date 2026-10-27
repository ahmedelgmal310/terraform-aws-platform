output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.vpc.private_subnet_ids
}

output "nat_public_ips" {
  description = "Egress IPs to allow-list with third parties."
  value       = module.vpc.nat_public_ips
}

output "artifacts_bucket" {
  description = "Artifacts bucket name."
  value       = module.artifacts_bucket.bucket_id
}

output "ecs_cluster_name" {
  description = "ECS cluster name."
  value       = module.app.cluster_name
}

output "db_endpoint" {
  description = "PostgreSQL endpoint."
  value       = module.db.endpoint
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master password."
  value       = module.db.master_user_secret_arn
}

output "deploy_role_arn" {
  description = "Role assumed by the GitHub deploy workflow."
  value       = module.deploy_role.role_arn
}
