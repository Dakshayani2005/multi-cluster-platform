# Runbook: Onboarding a New Engineering Team

**Category:** Platform Operations  
**Last Updated:** 2025-01-01  
**Owner:** Platform Engineering Team  
**Estimated Time:** 30–60 minutes

---

## Overview

This runbook guides platform operators through the process of onboarding a new engineering team onto the multi-cluster IDP. After following these steps, the team will have an isolated namespace, RBAC permissions, resource quotas, network policies, and access to the Backstage portal.

---

## Prerequisites

- `kubectl` access to the management, staging, and production clusters
- ArgoCD CLI (`argocd`) configured and authenticated
- AWS CLI with appropriate IAM permissions
- The new team's GitHub group name and roster

---

## Step 1: Create the Team Namespace via Self-Service (Preferred)

1. Direct the team lead to the Backstage portal at `https://backstage.example.com`
2. Navigate to **Create** → **Provision Team Namespace**
3. Fill in:
   - Team name (e.g., `team-gamma`)
   - Environment (`staging` first, then `production` once stable)
   - Resource requirements
4. Submit the form — a GitHub Pull Request will be opened automatically
5. A platform engineer reviews and merges the PR
6. ArgoCD automatically applies the namespace manifests within 2–3 minutes

---

## Step 2: Manual Namespace Creation (If Self-Service Unavailable)

Apply namespace manifests directly:

```bash
TEAM=team-gamma
ENVIRONMENT=staging

# Create namespace manifest
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${TEAM}
  labels:
    team: ${TEAM}
    environment: ${ENVIRONMENT}
    istio-injection: enabled
EOF

# Apply resource quota
kubectl apply -f rbac/team-namespaces.yaml

# Apply network policies
kubectl apply -f rbac/network-policies.yaml
```

---

## Step 3: Configure RBAC

Map the team's GitHub/SSO group to the namespace RBAC:

```bash
# Update the RoleBinding for the new team
kubectl create rolebinding ${TEAM}-developer-binding \
  --namespace=${TEAM} \
  --role=team-developer \
  --group=${TEAM}-developers \
  --dry-run=client -o yaml | kubectl apply -f -
```

For AWS EKS, update the `aws-auth` ConfigMap to map the team's IAM role:

```bash
eksctl create iamidentitymapping \
  --cluster production-cluster \
  --region eu-west-1 \
  --arn arn:aws:iam::ACCOUNT_ID:role/${TEAM}-developer-role \
  --group ${TEAM}-developers \
  --username ${TEAM}-developer
```

---

## Step 4: Register Team in Backstage

Add a `catalog-info.yaml` to the team's repository:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Group
metadata:
  name: team-gamma
  title: Team Gamma
spec:
  type: team
  members: [alice, bob, charlie]
```

Register it via the Backstage API or by adding the URL to `app-config.yaml` catalog locations.

---

## Step 5: Verify Onboarding

```bash
# Verify namespace exists
kubectl get namespace ${TEAM}

# Verify resource quota
kubectl describe resourcequota -n ${TEAM}

# Verify network policies
kubectl get networkpolicies -n ${TEAM}

# Verify RBAC
kubectl auth can-i create deployments --namespace=${TEAM} --as=system:serviceaccount:${TEAM}:default

# Verify ArgoCD project
argocd proj list | grep ${TEAM}
```

---

## Step 6: Communicate to Team

Send the team the following information:

- Namespace name: `${TEAM}`
- Cluster access command: `aws eks update-kubeconfig --name production-cluster --region eu-west-1`
- Backstage portal: `https://backstage.example.com`
- ArgoCD dashboard: `https://argocd.example.com`
- Monitoring dashboards: `https://grafana.example.com`

---

## Troubleshooting

| Issue | Resolution |
|-------|-----------|
| Namespace creation fails | Check OPA Gatekeeper policies; ensure required labels are set |
| RBAC not taking effect | Verify `aws-auth` ConfigMap is updated; check IAM role ARN |
| ArgoCD app not syncing | Check ArgoCD project permissions; verify repo URL is correct |
| Network policies blocking traffic | Review NetworkPolicy selectors; check Istio sidecar injection |

---

## Rollback

To remove a team namespace:

```bash
# DANGER: This deletes all resources in the namespace
kubectl delete namespace ${TEAM}

# Remove from ArgoCD
argocd app delete ${TEAM}-apps

# Remove IAM identity mapping
eksctl delete iamidentitymapping --cluster production-cluster --arn arn:aws:iam::ACCOUNT_ID:role/${TEAM}-developer-role
```
