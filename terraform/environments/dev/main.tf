# Dev environment root module

locals {
  petclinic_services = [
    "config-server",
    "discovery-server",
    "api-gateway",
    "customers-service",
    "visits-service",
    "vets-service",
    "genai-service",
    "admin-server",
  ]
}

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment
  vpc_cidr    = "10.0.0.0/16"

  public_subnet_cidrs = [
    "10.0.1.0/24",
    "10.0.2.0/24",
  ]

  availability_zones = [
    "eu-central-1a",
    "eu-central-1b",
  ]
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id

  node_instance_types = ["t4g.small"]
  node_min_size       = 2
  node_max_size       = 8
  node_desired_size   = 8

  cluster_admin_arns = var.cluster_admin_arns
}

module "ecr" {
  source = "../../modules/ecr"

  project              = var.project
  environment          = var.environment
  service_names        = local.petclinic_services
  image_tag_mutability = "MUTABLE"
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class          = "db.t4g.micro"
  multi_az                = false
  skip_final_snapshot     = true
  backup_retention_period = 7
}

module "dns" {
  source = "../../modules/dns"

  project           = var.project
  environment       = var.environment
  domain_name       = var.domain_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  alb_dns_name      = var.alb_dns_name
}

module "secrets" {
  source = "../../modules/secrets"

  project                = var.project
  environment            = var.environment
  openai_api_key         = var.openai_api_key
  grafana_admin_password = var.grafana_admin_password
  oidc_provider_arn      = module.eks.oidc_provider_arn
  oidc_provider_url      = module.eks.oidc_provider_url
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  project     = var.project
  environment = var.environment
  github_repo = var.github_repo
}

module "karpenter" {
  source = "../../modules/karpenter"

  project           = var.project
  environment       = var.environment
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  node_role_arn     = module.eks.node_role_arn
}

resource "aws_budgets_budget" "monthly" {
  name         = "petclinic-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
