output "cluster_arn" {
  description = "ARN of the ECS cluster."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "ARN of the current task definition revision."
  value       = aws_ecs_task_definition.this.arn
}

output "security_group_id" {
  description = "Security group of the tasks; allow it on downstream resources such as the database."
  value       = aws_security_group.this.id
}

output "task_role_name" {
  description = "Name of the application role; attach workload permissions to it."
  value       = aws_iam_role.task.name
}

output "task_role_arn" {
  description = "ARN of the application role."
  value       = aws_iam_role.task.arn
}

output "execution_role_arn" {
  description = "ARN of the task execution role."
  value       = aws_iam_role.execution.arn
}

output "log_group_name" {
  description = "CloudWatch Logs group of the containers."
  value       = aws_cloudwatch_log_group.this.name
}
