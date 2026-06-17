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
