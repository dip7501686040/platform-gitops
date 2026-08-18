module "network" {
  source = "./modules/network"

  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway
  tags               = var.tags
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = var.ecr_repository_names
  tags             = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = var.cluster_name
  k8s_version         = var.k8s_version
  private_subnet_ids  = module.network.private_subnet_ids
  public_subnet_ids   = module.network.public_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  enable_irsa_addons  = var.enable_irsa_addons
  tags                = var.tags
}

module "addons" {
  source = "./modules/addons"

  enable_irsa_addons = var.enable_irsa_addons
  cluster_name       = var.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  tags               = var.tags
}

module "jenkins_ec2" {
  count  = var.jenkins_mode == "ec2" ? 1 : 0
  source = "./modules/jenkins-ec2"

  instance_type        = var.jenkins_instance_type
  admin_cidr           = var.jenkins_admin_cidr
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.public_subnet_ids[0]
  github_push_username = var.github_push_username
  github_push_token    = var.github_push_token
  service_names        = var.ecr_repository_names
  tags                 = var.tags
}
