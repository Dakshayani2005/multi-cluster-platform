#!/usr/bin/env bash
set -euo pipefail

echo "==> WARNING: This will destroy ALL platform resources."
read -rp "Type 'yes' to confirm: " CONFIRM
[ "$CONFIRM" != "yes" ] && echo "Aborted." && exit 1

echo "==> Tearing down platform..."

# Remove ArgoCD applications (prevents resource deletion conflicts)
argocd app delete platform-root --cascade 2>/dev/null || true

# Destroy Terraform infrastructure (all clusters)
for ENV in production staging management; do
  echo "--> Destroying ${ENV} cluster infrastructure..."
  cd infra/terraform/${ENV}
  terraform destroy -auto-approve
  cd ../../..
done

echo "==> Teardown complete. All resources destroyed."
