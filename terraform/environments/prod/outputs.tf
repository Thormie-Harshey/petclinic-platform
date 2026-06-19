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

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL for the prod environment"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service name to ECR repository ARN for the prod environment"
  value       = module.ecr.repository_arns
}

output "rds_endpoint" {
  description = "RDS instance endpoint hostname — use in SPRING_DATASOURCE_URL"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS instance port (3306)"
  value       = module.rds.port
}

output "rds_db_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS credentials — used by External Secrets Operator"
  value       = module.rds.secret_arn
}

output "rds_connection_string" {
  description = "JDBC connection string for Spring Boot services — jdbc:mysql://{endpoint}:3306/petclinic"
  value       = "jdbc:mysql://${module.rds.endpoint}:${module.rds.port}/petclinic"
}
