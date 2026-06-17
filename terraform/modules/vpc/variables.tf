variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets — one per availability zone"
  type        = list(string)
}

variable "availability_zones" {
  description = "List of availability zones — must match the length of public_subnet_cidrs"
  type        = list(string)
}

variable "tags" {
  description = "Supplementary tags merged onto every resource. Required tags (Project, Environment, ManagedBy) are injected by the caller's AWS provider default_tags block and do not need to be repeated here."
  type        = map(string)
  default     = {}
}
