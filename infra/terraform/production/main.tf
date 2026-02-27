module "production_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "production-cluster"
  cluster_version = "1.29"
  region          = "eu-west-1"
  vpc_cidr        = "10.2.0.0/16"
  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.2.101.0/24", "10.2.102.0/24"]
  public_subnets  = ["10.2.1.0/24", "10.2.2.0/24"]
  node_desired    = 2
  node_min        = 2
  node_max        = 4
}

output "cluster_name"     { value = module.production_cluster.cluster_name }
output "cluster_endpoint" { value = module.production_cluster.cluster_endpoint }
