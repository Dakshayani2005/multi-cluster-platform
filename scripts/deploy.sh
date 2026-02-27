#!/usr/bin/env bash
set -euo pipefail

echo "==> Deploying platform components via GitOps..."

kubectl config use-context management-cluster

# Install ArgoCD
echo "--> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.4/manifests/install.yaml
kubectl apply -f gitops-repo/platform/argocd/argocd-install.yaml

echo "--> Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Retrieve ArgoCD initial admin password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "--> ArgoCD admin password: ${ARGOCD_PASSWORD}"

# Login to ArgoCD
argocd login --insecure --username admin --password "${ARGOCD_PASSWORD}" \
  "$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

# Register remote clusters
echo "--> Registering workload clusters with ArgoCD..."
argocd cluster add staging-cluster --yes
argocd cluster add production-cluster --yes

# Bootstrap platform via app-of-apps
echo "--> Bootstrapping platform root application..."
kubectl apply -f gitops-repo/platform/argocd/platform-root-app.yaml

# Install Istio on management cluster (primary)
echo "--> Installing Istio (primary cluster)..."
istioctl install -f platform/istio/primary-cluster.yaml -y

# Install Istio on remote clusters
for CLUSTER in staging-cluster production-cluster; do
  echo "--> Installing Istio remote on ${CLUSTER}..."
  ISTIOD_ADDR=$(kubectl get svc istio-eastwestgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  kubectl config use-context "${CLUSTER}"
  CLUSTER_NAME=${CLUSTER} EXTERNAL_ISTIOD_ADDR=${ISTIOD_ADDR} \
    envsubst < platform/istio/remote-cluster.yaml | kubectl apply -f -

  kubectl config use-context management-cluster
  istioctl create-remote-secret --name="${CLUSTER}" --context="${CLUSTER}" | kubectl apply -f -
done

# Apply Istio mesh configs
echo "--> Applying Istio mesh configuration..."
kubectl apply -f platform/istio/mtls.yaml
kubectl apply -f platform/istio/service-entries.yaml
kubectl apply -f platform/istio/gateways.yaml
kubectl apply -f platform/istio/virtualservice.yaml

# Install OPA Gatekeeper
echo "--> Installing OPA Gatekeeper..."
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system --create-namespace \
  --version 3.16.3 \
  --wait

# Apply policies to all clusters
for CLUSTER in management-cluster staging-cluster production-cluster; do
  echo "--> Applying OPA policies to ${CLUSTER}..."
  kubectl config use-context "${CLUSTER}"
  kubectl apply -f policies/gatekeeper/
done
kubectl config use-context management-cluster

# Apply RBAC and network policies
echo "--> Applying RBAC and network policies..."
for CLUSTER in staging-cluster production-cluster; do
  kubectl config use-context "${CLUSTER}"
  kubectl apply -f rbac/team-namespaces.yaml
  kubectl apply -f rbac/network-policies.yaml
done
kubectl config use-context management-cluster

# Deploy observability stack
echo "--> Deploying observability stack..."
kubectl apply -f platform/observability/prometheus/prometheus-thanos.yaml
kubectl apply -f platform/observability/thanos/thanos-query-store.yaml
kubectl apply -f platform/observability/loki/loki-stack.yaml
kubectl apply -f platform/observability/jaeger/jaeger-tracing.yaml

echo "==> Platform deployment complete!"
echo "    ArgoCD:   https://$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "    Grafana:  http://$(kubectl get svc grafana -n observability -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'):3000"
