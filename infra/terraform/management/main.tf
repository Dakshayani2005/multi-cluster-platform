module "management_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name    = "management-cluster"
  cluster_version = "1.29"
  region          = "us-east-1"
  vpc_cidr        = "10.0.0.0/16"
  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  node_desired    = 2
  node_min        = 1
  node_max        = 3
}

output "cluster_name"     { value = module.management_cluster.cluster_name }
output "cluster_endpoint" { value = module.management_cluster.cluster_endpoint }
