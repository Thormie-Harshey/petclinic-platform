variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group — use the public subnets from the VPC module"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS security group ID (allows port 3306 from EKS node SG only)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class — db.t4g.micro is free-tier eligible (Graviton)"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB — 20 GB is free-tier eligible"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage ceiling for RDS autoscaling in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ for high availability — false for cost optimization (learning environment)"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups (7 for dev, 30 for prod)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "skip_final_snapshot" {
  description = "Skip final DB snapshot when the instance is deleted (true for dev, false for prod)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Prevent accidental deletion of the DB instance"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Name of the initial database to create on the RDS instance"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "petclinic"
  sensitive   = true
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
