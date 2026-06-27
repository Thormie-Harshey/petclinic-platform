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
    error_message = "environment must be dev or prod."
  }
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service — set in terraform.tfvars, never hardcode"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password — set in terraform.tfvars, never hardcode. Min 12 chars."
  type        = string
  sensitive   = true
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN of the EKS cluster — used to create the ESO IRSA role"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix — used in ESO IRSA trust policy"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
