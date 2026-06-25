variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Target environment for ECR push permissions (dev or prod)"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be dev or prod"
  }
}

variable "role_name" {
  description = "IAM role name assumed by GitHub Actions"
  type        = string
  default     = "petclinic-github-actions-role"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume this role — format: org/repo (e.g. Thormie-Harshey/petclinic-app)"
  type        = string
}

variable "aws_region" {
  description = "AWS region where ECR repositories are hosted"
  type        = string
  default     = "eu-central-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
