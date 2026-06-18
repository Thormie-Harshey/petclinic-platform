variable "project" {
  description = "Project name, used in resource naming and tagging"
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

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster — must be 1.31 or later (1.29 reached EoL March 2025)"
  type        = string
  default     = "1.32"

  validation {
    condition     = tonumber(split(".", var.cluster_version)[1]) >= 31
    error_message = "cluster_version must be 1.31 or later. EKS 1.29 and 1.30 are end-of-life."
  }
}

variable "subnet_ids" {
  description = "List of public subnet IDs for the EKS cluster and managed node group"
  type        = list(string)
}

variable "cluster_sg_id" {
  description = "Security group ID for the EKS cluster control plane (cross-account ENIs)"
  type        = string
}

variable "node_sg_id" {
  description = "Security group ID for EKS worker nodes — attached via launch template"
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group — must be ARM64 (Graviton) to match ami_type AL2_ARM_64"
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for EKS nodes — AL2_ARM_64 for Graviton t4g instances"
  type        = string
  default     = "AL2_ARM_64"
}

variable "node_min_size" {
  description = "Minimum number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of nodes in the managed node group"
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group"
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "EBS root volume size in GB for each node — 20 GB fits within the 30 GB EBS free tier"
  type        = number
  default     = 20
}

variable "allowed_public_cidrs" {
  description = "CIDRs permitted to reach the EKS public API endpoint — restrict to office/VPN/CI IPs in production; defaults to open for convenience in learning environments"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_admin_arns" {
  description = "IAM ARNs (users or roles) that receive EKS cluster admin access via access entries — include the ARN of the deploying principal"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags merged onto all resources created by this module"
  type        = map(string)
  default     = {}
}
