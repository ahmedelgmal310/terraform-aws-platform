output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones used by the subnets, in subnet order."
  value       = var.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (NAT egress), one per AZ."
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "IDs of the intra subnets (no internet route), one per AZ."
  value       = aws_subnet.intra[*].id
}

output "public_subnet_cidrs" {
  description = "CIDR blocks of the public subnets."
  value       = local.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of the private subnets."
  value       = local.private_subnet_cidrs
}

output "intra_subnet_cidrs" {
  description = "CIDR blocks of the intra subnets."
  value       = local.intra_subnet_cidrs
}

output "private_route_table_ids" {
  description = "IDs of the per-AZ private route tables."
  value       = aws_route_table.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways (empty when nat_gateway_mode is none)."
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "Elastic IPs attached to the NAT gateways, useful for allow-listing egress."
  value       = aws_eip.nat[*].public_ip
}

output "flow_log_id" {
  description = "ID of the VPC flow log, or null when disabled."
  value       = try(aws_flow_log.this[0].id, null)
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving flow logs, or null when disabled."
  value       = try(aws_cloudwatch_log_group.flow_logs[0].name, null)
}
