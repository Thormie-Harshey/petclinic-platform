output "endpoint" {
  description = "RDS instance endpoint hostname (without port)"
  value       = aws_db_instance.main.address
}

output "port" {
  description = "RDS instance port (3306 for MySQL)"
  value       = aws_db_instance.main.port
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "secret_arn" {
  description = "Secrets Manager ARN for RDS credentials — petclinic/{env}/rds-credentials"
  value       = aws_secretsmanager_secret.rds_credentials.arn
}
