locals {
  common_tags = {
    Project     = "cloudforge"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name                 = var.cluster_name
  cidr_block           = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  cluster_name         = var.cluster_name
  tags                 = local.common_tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_names = ["cloudforge/backend", "cloudforge/frontend"]
  tags             = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  tags                = local.common_tags
}

module "rds" {
  source = "../../modules/rds"

  identifier                 = var.cluster_name
  instance_class             = var.db_instance_class
  allocated_storage          = var.db_allocated_storage
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  tags                       = local.common_tags
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  github_org          = var.github_org
  github_repo         = var.github_repo
  ecr_repository_arns = values(module.ecr.repository_arns)
  tags                = local.common_tags
}
