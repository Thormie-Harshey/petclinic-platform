variable "project" {
  description = "Project name used as a prefix in repository names"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be 'dev' or 'prod'."
  }
}

variable "service_names" {
  description = "List of microservice names — one ECR repository is created per entry"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for ECR repositories: MUTABLE (dev) or IMMUTABLE (prod)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be 'MUTABLE' or 'IMMUTABLE'."
  }
}

variable "tags" {
  description = "Additional resource tags merged with module-level defaults"
  type        = map(string)
  default     = {}
}
