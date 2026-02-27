# Runbook: Responding to a Regional Outage

**Category:** Incident Response  
**Last Updated:** 2025-01-01  
**Owner:** Platform Engineering Team  
**Severity:** P0 – Critical  
**Estimated Resolution Time:** 15–45 minutes for failover

---

## Overview

This runbook guides on-call engineers through the steps to detect, respond to, and recover from a regional AWS availability zone or full-region outage affecting the multi-cluster platform. The platform is designed to automatically failover traffic via Istio locality-aware load balancing, but manual intervention may be needed for a full region failure.

---

## Detection

### Automated Alerts

The following Prometheus/Grafana alerts will fire during a regional outage:

- `ClusterUnreachable` — ArgoCD cannot reach a managed cluster
- `PrometheusTargetMissing` — Thanos Sidecar metrics stop flowing from a cluster
- `IstioPilotDisconnected` — Remote cluster loses connection to primary istiod
- `RegionalErrorRateHigh` — HTTP 5xx rate exceeds 5% from a specific region

### Manual Verification

```bash
# Check cluster connectivity from management cluster
kubectl get clusters -A   # Cluster API status
argocd cluster list       # ArgoCD cluster health

# Check Istio remote cluster status
istioctl remote-clusters

# Check Thanos global query for missing cluster data
curl http://thanos-query.monitoring.svc.cluster.local:9090/api/v1/targets
```

---

## Immediate Response (0–5 minutes)

### 1. Acknowledge the incident

```bash
# Set incident status in your on-call tool (PagerDuty, OpsGenie, etc.)
# Create incident channel: #incident-YYYY-MM-DD-region-outage
```

### 2. Confirm the outage scope

```bash
# Check AWS Service Health Dashboard
open https://health.aws.amazon.com/health/status

# Check which clusters are affected
kubectl get nodes --context=production-cluster 2>&1 | head -20
kubectl get nodes --context=staging-cluster 2>&1 | head -20
```

---

## Traffic Failover (5–15 minutes)

### Automatic Failover (Istio handles this)

Istio's locality-aware load balancing automatically routes traffic away from unhealthy endpoints. Verify it's working:

```bash
# Check if Istio has detected the unhealthy endpoints
istioctl proxy-config endpoints deploy/istio-ingressgateway -n istio-system | grep UNHEALTHY

# Check that traffic is flowing to healthy region
kubectl logs -n istio-system -l app=istio-ingressgateway --tail=50 | grep "eu-west"
```

### Manual Failover (If Automatic Failover Fails)

Force all traffic to the healthy region by updating the DestinationRule:

```bash
# Drain the affected region (e.g., eu-west-1 is down, redirect to us-east-1)
kubectl patch destinationrule web-app -n app --type=merge -p '{
  "spec": {
    "trafficPolicy": {
      "loadBalancer": {
        "localityLbSetting": {
          "distribute": [
            {
              "from": "*",
              "to": {"us-east-1/*": 100}
            }
          ]
        }
      }
    }
  }
}'

# Apply the manual failover
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: web-app
  namespace: app
spec:
  hosts:
    - web-service
    - web-app.example.com
  http:
    - route:
        - destination:
            host: web-service
            subset: v1
          weight: 100
      headers:
        request:
          set:
            x-failover-reason: "regional-outage-eu-west-1"
EOF
```

---

## Validation (15–30 minutes)

```bash
# Verify traffic is reaching healthy endpoints
kubectl exec -n app deploy/web-app -- curl -s http://web-service/healthz

# Check error rate in Grafana
open https://grafana.example.com/d/platform-overview

# Check Thanos for cross-cluster metric availability
curl "http://thanos-query.monitoring.svc.cluster.local:9090/api/v1/query?query=up{cluster='management-cluster'}"

# Confirm ArgoCD is showing healthy apps
argocd app list | grep -v Healthy
```

---

## Recovery (After Region Restores)

```bash
# Revert the manual failover DestinationRule
kubectl apply -f platform/istio/virtualservice.yaml

# Re-register the recovered cluster with ArgoCD if needed
argocd cluster add production-cluster

# Verify Thanos Sidecar reconnection
kubectl get pods -n monitoring --context=production-cluster

# Trigger ArgoCD sync for all apps in recovered cluster
argocd app sync --selector cluster=production-cluster
```

---

## Post-Incident

1. Confirm all metrics are flowing in Thanos Query
2. Verify all ArgoCD apps are `Healthy` and `Synced`
3. Run `scripts/verify.sh` to confirm platform health
4. Write an incident report covering:
   - Timeline of events
   - Root cause
   - Impact scope
   - Mitigation steps taken
   - Action items to prevent recurrence

---

## Escalation

| Situation | Escalation Path |
|-----------|----------------|
| Failover not working after 15 minutes | Page Platform Lead |
| Data loss suspected | Page Data Engineering Lead + VP Engineering |
| Full platform unavailable > 30 minutes | Escalate to CTO |
