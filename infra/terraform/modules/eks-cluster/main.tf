variable "cluster_name"    { type = string }
variable "cluster_version" { type = string; default = "1.29" }
variable "vpc_cidr"        { type = string }
variable "region"          { type = string }
variable "azs"             { type = list(string) }
variable "private_subnets" { type = list(string) }
variable "public_subnets"  { type = list(string) }
variable "node_desired"    { type = number; default = 2 }
variable "node_min"        { type = number; default = 1 }
variable "node_max"        { type = number; default = 4 }
variable "instance_types"  { type = list(string); default = ["t3.medium"] }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    Environment = var.cluster_name
    ManagedBy   = "terraform"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  eks_managed_node_groups = {
    default = {
      desired_size   = var.node_desired
      min_size       = var.node_min
      max_size       = var.node_max
      instance_types = var.instance_types
      capacity_type  = "ON_DEMAND"

      labels = {
        Environment = var.cluster_name
      }
    }
  }

  tags = {
    Environment = var.cluster_name
    ManagedBy   = "terraform"
    Platform    = "multi-cluster-idp"
  }
}

output "cluster_name"              { value = module.eks.cluster_name }
output "cluster_endpoint"          { value = module.eks.cluster_endpoint }
output "cluster_ca_certificate"    { value = module.eks.cluster_certificate_authority_data }
output "cluster_oidc_issuer_url"   { value = module.eks.cluster_oidc_issuer_url }
output "vpc_id"                    { value = module.vpc.vpc_id }
