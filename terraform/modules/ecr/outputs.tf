output "repository_urls" {
  description = "Map of service name to ECR repository URL (used for image pushes and K8s image references)"
  value       = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of service name to ECR repository ARN (used for IAM policy scoping)"
  value       = { for k, v in aws_ecr_repository.service : k => v.arn }
}
