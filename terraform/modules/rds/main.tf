locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "random_password" "master" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-${var.environment}-db-subnet-group"
  description = "DB subnet group for ${var.project}-${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-db-subnet-group"
  }, var.tags)
}

resource "aws_db_parameter_group" "main" {
  name        = "${var.project}-${var.environment}-mysql8"
  family      = "mysql8.0"
  description = "MySQL 8.0 parameter group for ${var.project}-${var.environment}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-mysql8"
  }, var.tags)
}

resource "aws_db_instance" "main" {
  identifier = "${var.project}-${var.environment}-mysql"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az                   = var.multi_az
  publicly_accessible        = false
  backup_retention_period    = var.backup_retention_period
  backup_window              = "03:00-04:00"
  maintenance_window         = "mon:04:00-mon:05:00"
  auto_minor_version_upgrade = true

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = "${var.project}-${var.environment}-mysql-final-snapshot"
  deletion_protection       = var.deletion_protection

  lifecycle {
    # Prevents Terraform from resetting the password after initial creation.
    # To rotate the password: update the secret in Secrets Manager, then update RDS manually.
    ignore_changes = [password]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-mysql"
  }, var.tags)
}

resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "petclinic/${var.environment}/rds-credentials"
  description = "RDS master credentials for ${var.project}-${var.environment} MySQL"

  tags = merge(local.common_tags, {
    Name = "petclinic/${var.environment}/rds-credentials"
  }, var.tags)
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = sensitive(jsonencode({
    username = var.db_username
    password = random_password.master.result
  }))
}
