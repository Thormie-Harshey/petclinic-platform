output "openai_secret_arn" {
  description = "Secrets Manager ARN for the OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.arn
}

output "openai_secret_name" {
  description = "Secrets Manager name for the OpenAI API key — referenced in the ExternalSecret remoteRef.key"
  value       = aws_secretsmanager_secret.openai_api_key.name
}

output "eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator — pass to scripts/install-eso.sh"
  value       = aws_iam_role.eso.arn
}

output "eso_role_name" {
  description = "IRSA role name for External Secrets Operator"
  value       = aws_iam_role.eso.name
}
