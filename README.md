# Multi-Cluster Kubernetes Platform (Internal Developer Platform)

## Overview

This repository implements an enterprise-grade, multi-cluster Kubernetes platform distributed across two AWS regions (`us-east-1` and `eu-west-1`). It serves as an Internal Developer Platform (IDP) with centralized GitOps, multi-cluster service mesh, full observability, policy enforcement, and developer self-service.

---

## Repository Structure

```
.
├── infra/
│   └── terraform/
│       ├── modules/eks-cluster/     # Reusable EKS cluster module
│       ├── management/              # Management cluster (us-east-1)
│       ├── staging/                 # Staging cluster (eu-west-1)
│       └── production/              # Production cluster (eu-west-1)
│
├── gitops-repo/                     # ArgoCD-managed GitOps source of truth
│   ├── platform/
│   │   ├── argocd/                  # ArgoCD install + cluster registrations
│   │   ├── istio/                   # Istio ArgoCD app
│   │   ├── gatekeeper/              # OPA Gatekeeper ArgoCD app
│   │   └── observability/           # Observability ArgoCD app
│   ├── apps/
│   │   └── web-app/                 # Sample app manifests (deployment + service)
│   └── clusters/
│       ├── production/              # app-of-apps for production cluster
│       └── staging/                 # app-of-apps for staging cluster
│
├── platform/
│   ├── federation/                  # Cluster API cluster definitions
│   ├── istio/                       # Istio configs (primary, remote, mTLS, gateways, ServiceEntry, VirtualService)
│   ├── observability/
│   │   ├── prometheus/              # Prometheus + Thanos sidecar
│   │   ├── thanos/                  # Thanos Query + Store (management cluster)
│   │   ├── loki/                    # Loki + Promtail DaemonSet
│   │   └── jaeger/                  # Jaeger + Grafana + Istio tracing config
│   └── staging/
│       └── database/                # PostgreSQL StatefulSet (secrets via ExternalSecret)
│
├── policies/
│   └── gatekeeper/
│       ├── install.yaml
│       ├── disallow-privileged-containers.yaml
│       ├── require-resource-limits.yaml
│       └── require-labels.yaml
│
├── rbac/
│   ├── team-namespaces.yaml         # Namespaces, ResourceQuotas, Roles, RoleBindings
│   └── network-policies.yaml        # Default-deny + allowlist NetworkPolicies
│
├── iam/
│   └── ebs-csi-policy.json          # Least-privilege IAM policy for EBS CSI driver
│
├── backstage/
│   ├── app-config.yaml              # Backstage configuration
│   ├── catalog/
│   │   └── all-components.yaml      # Service catalog entries
│   └── templates/
│       ├── new-microservice/        # Template: scaffold new microservice + CI/CD
│       └── provision-namespace/     # Template: self-service namespace provisioning
│
├── chaos/
│   └── chaos-experiments.md         # Node failure + regional outage experiments
│
├── runbooks/
│   ├── onboarding-new-team.md
│   ├── regional-outage-response.md
│   └── disaster-recovery.md
│
├── scripts/
│   ├── setup.sh                     # Provision infra (terraform)
│   ├── deploy.sh                    # Deploy platform components
│   ├── test.sh                      # Health checks
│   ├── verify.sh                    # Cross-cluster + failover + policy tests
│   └── teardown.sh                  # Destroy all resources
│
├── ARCHITECTURE.md
├── README.md
└── submission.yml
```

---

## Platform Architecture

| Cluster | Region | Role |
|---------|--------|------|
| management-cluster | us-east-1 | Hosts ArgoCD, Thanos Query, Grafana, Backstage, Istio primary control plane |
| staging-cluster | eu-west-1 | Staging workloads; Istio remote; Thanos sidecar; Promtail |
| production-cluster | eu-west-1 | Production workloads; Istio remote; Thanos sidecar; Promtail |

---

## Quick Start

### Prerequisites

- Terraform >= 1.5.0
- kubectl >= 1.27
- AWS CLI >= 2.0
- ArgoCD CLI >= 2.10
- istioctl >= 1.21
- Helm >= 3.14

### Deploy

```bash
# 1. Provision clusters
bash scripts/setup.sh

# 2. Deploy all platform components
bash scripts/deploy.sh

# 3. Deploy sample application
argocd app sync production-web-app

# 4. Run health checks
bash scripts/test.sh

# 5. Run full verification (failover, policies)
bash scripts/verify.sh
```

---

## Key Features

### Multi-Cluster Federation (Cluster API)
Three EKS clusters managed from a central management plane via Cluster API. See `platform/federation/`.

### Service Mesh (Istio — Primary-Remote)
- Management cluster runs Istio primary (istiod)
- Staging and production are remote clusters with shared control plane
- Global STRICT mTLS across all namespaces (`platform/istio/mtls.yaml`)
- East-West gateways for cross-cluster service discovery (`platform/istio/service-entries.yaml`)
- Canary 90/10 traffic split with locality-based automatic failover

### GitOps (ArgoCD — App-of-Apps)
- `gitops-repo/platform/argocd/platform-root-app.yaml` bootstraps all platform addons
- `gitops-repo/clusters/*/app-of-apps.yaml` manages application workloads
- All changes via Git PR → automatic ArgoCD sync

### Observability
- **Metrics**: Prometheus per cluster → Thanos Sidecar → Thanos Query (global view)
- **Logs**: Promtail DaemonSet per cluster → centralized Loki
- **Traces**: Jaeger (OTLP) integrated with Istio Telemetry (10% sampling)
- **Dashboards**: Grafana with Thanos, Loki, and Jaeger datasources

### Policy Enforcement (OPA Gatekeeper)
Three enforced policies across all clusters:
1. Disallow privileged containers
2. Require CPU and memory limits/requests
3. Require `app`, `team`, and `environment` labels on all pods

### Multi-Tenancy (RBAC + NetworkPolicies)
- Team namespaces with `ResourceQuota`, `Role`, `RoleBinding`
- Default-deny `NetworkPolicy` in each team namespace
- Allowlist rules for intra-namespace, DNS, Istio, and monitoring traffic

### Developer Portal (Backstage)
- Service catalog with ownership and CI/CD status
- **Template 1**: Scaffold a new microservice (Kubernetes manifests + GitHub Actions CI/CD)
- **Template 2**: Self-service namespace provisioning (opens GitOps PR automatically)

---

## Security Notes

- No secrets are hardcoded; PostgreSQL credentials use Kubernetes `ExternalSecret` referencing AWS Secrets Manager
- IAM policies are least-privilege with resource-scoped ARNs (no `Resource: "*"`)
- All containers run as non-root with `allowPrivilegeEscalation: false`
- OPA Gatekeeper enforces resource limits on all workloads at admission time
