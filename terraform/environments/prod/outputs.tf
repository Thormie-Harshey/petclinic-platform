# Prod environment outputs

output "vpc_id" {
  description = "ID of the prod VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets in prod"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "ID of the EKS cluster security group in prod"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "ID of the EKS node security group in prod"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "ID of the RDS security group in prod"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ID of the ALB security group in prod"
  value       = module.vpc.alb_sg_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN for creating IRSA roles"
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "OIDC provider URL (without https://) for IRSA trust policies"
  value       = module.eks.oidc_provider_url
}

output "eks_node_role_arn" {
  description = "IAM role ARN for EKS worker nodes"
  value       = module.eks.node_role_arn
}

output "eks_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = module.eks.kubeconfig_command
}
