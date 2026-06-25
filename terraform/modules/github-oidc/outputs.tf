output "role_arn" {
  description = "ARN of the GitHub Actions IAM role — set as AWS_ROLE_ARN secret in the app repo"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
