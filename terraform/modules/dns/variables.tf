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

variable "domain_name" {
  description = "Root domain name for the Route 53 hosted zone (e.g. ashayelabs.xyz)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN of the EKS cluster — used to create the LB controller IRSA role"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// prefix (e.g. oidc.eks.eu-central-1.amazonaws.com/id/XXXXX)"
  type        = string
}

variable "alb_dns_name" {
  description = <<-EOT
    DNS hostname of the ALB created by the ingress controller.
    Leave null on first apply (ALB does not exist yet).
    After applying the Ingress manifest and the ALB is provisioned, run:
      kubectl get ingress -n petclinic-{env} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
    Then set this value in terraform.tfvars and run terraform apply again (PETPLAT-31).
  EOT
  type        = string
  default     = null
}

variable "alb_zone_id" {
  description = "Canonical hosted zone ID for ALBs in eu-central-1 — required for Route 53 alias records"
  type        = string
  default     = "Z215JYRZR1TBD5"
}

variable "tags" {
  description = "Additional tags to merge onto all resources"
  type        = map(string)
  default     = {}
}
