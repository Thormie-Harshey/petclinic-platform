variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "cluster_admin_arns" {
  description = "IAM ARNs (users or roles) granted EKS cluster admin access — set to your IAM user/role ARN in terraform.tfvars"
  type        = list(string)
  default     = []
}
