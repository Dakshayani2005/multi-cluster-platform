#!/usr/bin/env bash
set -euo pipefail

echo "==> Multi-Cluster Platform Setup"
echo "==> Provisioning infrastructure with Terraform..."

# Management cluster (us-east-1)
echo "--> Provisioning management cluster (us-east-1)..."
cd infra/terraform/management
terraform init -upgrade
terraform apply -auto-approve
MGMT_ENDPOINT=$(terraform output -raw cluster_endpoint)
cd ../../..

# Staging cluster (eu-west-1)
echo "--> Provisioning staging cluster (eu-west-1)..."
cd infra/terraform/staging
terraform init -upgrade
terraform apply -auto-approve
STAGING_ENDPOINT=$(terraform output -raw cluster_endpoint)
cd ../../..

# Production cluster (eu-west-1)
echo "--> Provisioning production cluster (eu-west-1)..."
cd infra/terraform/production
terraform init -upgrade
terraform apply -auto-approve
PROD_ENDPOINT=$(terraform output -raw cluster_endpoint)
cd ../../..

echo "==> Configuring kubeconfig contexts..."
aws eks update-kubeconfig --name management-cluster --region us-east-1 --alias management-cluster
aws eks update-kubeconfig --name staging-cluster --region eu-west-1 --alias staging-cluster
aws eks update-kubeconfig --name production-cluster --region eu-west-1 --alias production-cluster

echo "==> Installing Cluster API on management cluster..."
kubectl config use-context management-cluster
clusterctl init --infrastructure aws

echo "==> Applying federation configs for workload clusters..."
kubectl apply -f platform/federation/staging-cluster.yaml
kubectl apply -f platform/federation/production-cluster.yaml

echo "==> Setup complete!"
echo "    Management cluster:  ${MGMT_ENDPOINT}"
echo "    Staging cluster:     ${STAGING_ENDPOINT}"
echo "    Production cluster:  ${PROD_ENDPOINT}"
