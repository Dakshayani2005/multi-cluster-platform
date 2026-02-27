# Questionnaire Responses

---

## Q1: architecture_choice_justification

**What federation technology did you choose and why?**

I implemented **Cluster API (CAPI)** with the AWS provider (CAPA) for cluster federation, as defined in `platform/federation/staging-cluster.yaml` and `platform/federation/production-cluster.yaml`.

The choice came down to two candidates — KubeFed and Cluster API. KubeFed was ruled out because it has been archived by the Kubernetes community and is no longer actively maintained. Cluster API is the current standard, supported by SIG Cluster Lifecycle, and handles the full cluster lifecycle (provision, upgrade, scale, delete) rather than just config propagation.

In the implementation, the management cluster runs `capi-system` with the `AWSManagedControlPlane` resources defining each workload cluster. A `ClusterClass` named `eks-standard` (in `platform/federation/cluster-api-setup.yaml`) provides a reusable topology so new clusters can be added by instantiating the class rather than duplicating YAML. The workload clusters are defined as Kubernetes objects (`Cluster`, `AWSManagedControlPlane`, `AWSManagedMachinePool`) that CAPI reconciles against AWS APIs.

**Trade-offs considered:**
- CAPI adds a bootstrap dependency (must install CAPI before creating clusters), which is addressed by the `scripts/setup.sh` running `clusterctl init` before applying cluster manifests
- CAPI is more complex than KubeFed for pure config propagation, but the lifecycle management capability justifies this for a long-running platform

---

## Q2: service_mesh_topology

**What Istio topology did you implement and why?**

I implemented the **primary-remote (hub-and-spoke)** topology, as defined in `platform/istio/primary-cluster.yaml` (management cluster) and `platform/istio/remote-cluster.yaml` (staging and production clusters).

The management cluster runs `istiod` as the primary control plane. Staging and production clusters are configured as remote clusters using `profile: remote` — they run Envoy sidecars and east-west gateways but share the management cluster's istiod for certificate issuance, xDS config distribution, and service discovery.

Cross-cluster connectivity uses east-west gateways on port 15443 with `AUTO_PASSTHROUGH` TLS mode, as defined in `platform/istio/gateways.yaml`. `ServiceEntry` resources in `platform/istio/service-entries.yaml` register remote services into the local mesh using synthetic VIP addresses (240.0.0.x range).

Global STRICT mTLS is enforced by `platform/istio/mtls.yaml`, which places a `PeerAuthentication` in `istio-system` — this is mesh-wide scope, not namespace-scoped. All clusters share a common root CA establishing trust domain `mesh1`.

**Why primary-remote over multi-primary:**
Multi-primary runs istiod on every cluster, which provides higher availability if the management cluster fails. However, it requires synchronising two control planes and makes certificate management more complex. For this platform, the management cluster is itself highly available (multi-AZ EKS), making the added complexity of multi-primary unjustified.

---

## Q3: multi_tenancy_strategy

**How did you implement multi-tenancy?**

Multi-tenancy is implemented with three layers, all defined in `rbac/team-namespaces.yaml` and `rbac/network-policies.yaml`:

**1. RBAC isolation:** Each team namespace (`team-alpha`, `team-beta`) has a namespaced `Role` granting developers permission to manage their own `Deployments`, `Services`, `ConfigMaps`, and `Pods`, but only read access to `Secrets`. A `RoleBinding` links the team's GitHub/SSO group to this role. No team has permissions outside their namespace.

**2. Network isolation:** A default-deny `NetworkPolicy` blocks all ingress and egress by default. Explicit allowlist policies then permit: intra-namespace traffic, DNS egress (port 53), ingress from `istio-system` (for sidecar injection and traffic), and ingress from `monitoring` (for Prometheus scraping). This means team-alpha pods cannot reach team-beta pods without an explicit policy change reviewed by the platform team.

**3. Resource isolation:** Each namespace has a `ResourceQuota` capping CPU requests (4 cores), memory requests (8Gi), pods (20), services (10), and PVCs (5). This prevents a single team from exhausting cluster resources.

**OPA policies enforce baseline standards across all teams:** no privileged containers, mandatory resource limits, and required labels (`app`, `team`, `environment`). These apply at admission time before a pod even starts.

---

## Q4: gitops_structure

**Describe your GitOps repository structure and promotion workflow.**

The repository uses the **app-of-apps** pattern with a clear separation between platform configuration and application workloads:

```
gitops-repo/
├── platform/          ← platform add-ons (ArgoCD apps pointing to platform components)
│   ├── argocd/        ← ArgoCD install + cluster registration secrets
│   ├── istio/         ← Istio ArgoCD Application
│   ├── gatekeeper/    ← OPA Gatekeeper ArgoCD Application
│   └── observability/ ← Prometheus/Thanos/Loki/Jaeger ArgoCD Application
├── apps/              ← base application manifests (shared across environments)
│   └── web-app/
└── clusters/          ← environment-specific ArgoCD Application bindings
    ├── production/app-of-apps.yaml
    └── staging/app-of-apps.yaml
```

`platform-root-app.yaml` is the single bootstrap entrypoint — applying it to the management cluster causes ArgoCD to reconcile the entire `gitops-repo/platform/` directory and bring up all platform add-ons.

**Promotion workflow:** A developer's CI pipeline (`.github/workflows/ci.yaml` in the Backstage template skeleton) builds a Docker image on merge to `main`, tags it with the Git SHA, and updates `gitops-repo/apps/<service>/deployment.yaml` with the new image tag via a commit. ArgoCD detects the change through polling (or a webhook) and syncs staging automatically. Production sync requires either a manual ArgoCD approval or a separate merge to a `production` branch, giving the platform team a gate between environments.

---

## Q5: observability_approach

**How does your observability stack provide a global view?**

Each workload cluster runs a Prometheus instance (defined in `platform/observability/prometheus/prometheus-thanos.yaml`) co-located with a Thanos Sidecar. The sidecar does two things: it exposes a gRPC endpoint for Thanos Query to pull data in real-time, and it uploads completed 2-hour metric blocks to an S3 bucket (`multi-cluster-thanos-metrics`).

On the management cluster, Thanos Query (`platform/observability/thanos/thanos-query-store.yaml`) aggregates results from all cluster sidecars plus Thanos Store (which serves historical data from S3). This provides a single Prometheus-compatible query endpoint covering all clusters and all time ranges. Grafana points to this endpoint as its default datasource.

For logs, Promtail DaemonSets on every node ship container logs to the centralised Loki instance on the management cluster. Loki labels logs with cluster name and region, allowing cross-cluster log queries with a single LogQL expression.

For traces, the Istio `Telemetry` resource (`platform/observability/jaeger/jaeger-tracing.yaml`) configures the mesh to sample 10% of requests and forward spans to Jaeger via OTLP. Jaeger's data is surfaced in Grafana alongside metrics and logs, allowing operators to correlate a spike in error rate (Thanos), find the relevant log lines (Loki), and drill into a specific trace (Jaeger) from a single Grafana dashboard.
