module "staging_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "staging-cluster"
  cluster_version = "1.29"
  region          = "eu-west-1"
  vpc_cidr        = "10.1.0.0/16"
  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.1.101.0/24", "10.1.102.0/24"]
  public_subnets  = ["10.1.1.0/24", "10.1.2.0/24"]
  node_desired    = 2
  node_min        = 1
  node_max        = 3
}

output "cluster_name"     { value = module.staging_cluster.cluster_name }
output "cluster_endpoint" { value = module.staging_cluster.cluster_endpoint }
