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

variable "domain_name" {
  description = "Root domain name purchased on GoDaddy (e.g. ashayelabs.xyz) — set in terraform.tfvars"
  type        = string
}

variable "openai_api_key" {
  description = "OpenAI API key for genai-service — set in terraform.tfvars (gitignored, never commit)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "grafana_admin_password" {
  description = "Grafana admin password — set in terraform.tfvars (gitignored, never commit). Min 12 chars."
  type        = string
  sensitive   = true
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI role — format: org/repo (e.g. Thormie-Harshey/petclinic-app)"
  type        = string
  default     = "Thormie-Harshey/petclinic-app"
}

variable "budget_alert_email" {
  description = "Email address to receive AWS budget alert notifications"
  type        = string
}

variable "alb_dns_name" {
  description = <<-EOT
    DNS hostname of the ALB provisioned by the Ingress controller.
    Leave unset (or null) on first apply — the ALB does not exist yet.
    After applying k8s/base/ingress/ingress.yaml and the ALB is ready, run:
      kubectl get ingress -n petclinic-dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
    Then add  alb_dns_name = "<hostname>"  to terraform.tfvars and re-apply.
  EOT
  type        = string
  default     = null
}
