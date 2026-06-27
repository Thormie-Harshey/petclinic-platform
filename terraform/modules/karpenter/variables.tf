variable "project" {
  description = "Project name prefix used in resource names"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — used to scope IAM permissions to this specific cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster — used as Federated principal in IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without https:// — used as the condition key in IRSA trust policy"
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN for EKS worker nodes — Karpenter uses this role when launching new nodes (iam:PassRole scoped to this ARN)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
