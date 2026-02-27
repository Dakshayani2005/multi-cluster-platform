#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  if [ "$result" = "0" ]; then
    echo "  ✓ ${name}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${name}"
    FAIL=$((FAIL + 1))
  fi
}

echo "==> Running platform health checks..."

echo ""
echo "--- Cluster Connectivity ---"
kubectl cluster-info --context=management-cluster > /dev/null 2>&1; check "Management cluster reachable" $?
kubectl cluster-info --context=staging-cluster > /dev/null 2>&1; check "Staging cluster reachable" $?
kubectl cluster-info --context=production-cluster > /dev/null 2>&1; check "Production cluster reachable" $?

echo ""
echo "--- ArgoCD Health ---"
kubectl get deployment argocd-server -n argocd --context=management-cluster > /dev/null 2>&1; check "ArgoCD server deployed" $?
ARGOCD_SYNC=$(argocd app list -o json 2>/dev/null | jq -r '[.[] | select(.status.sync.status == "Synced")] | length')
check "ArgoCD apps synced (${ARGOCD_SYNC} apps)" $([ "$ARGOCD_SYNC" -gt "0" ] && echo 0 || echo 1)

echo ""
echo "--- Istio Service Mesh ---"
kubectl get pods -n istio-system --context=management-cluster | grep -q Running; check "Istio running (primary)" $?
kubectl get pods -n istio-system --context=staging-cluster 2>/dev/null | grep -q Running; check "Istio running (staging)" $?
kubectl get pods -n istio-system --context=production-cluster 2>/dev/null | grep -q Running; check "Istio running (production)" $?
kubectl get peerauthentication default -n istio-system --context=management-cluster > /dev/null 2>&1; check "Global mTLS policy exists" $?

echo ""
echo "--- OPA Gatekeeper Policies ---"
kubectl get constrainttemplate k8spspprivilegedcontainer --context=management-cluster > /dev/null 2>&1; check "Privileged container policy deployed" $?
kubectl get constrainttemplate k8srequiredresourcelimits --context=management-cluster > /dev/null 2>&1; check "Resource limits policy deployed" $?
kubectl get constrainttemplate k8srequiredlabels --context=management-cluster > /dev/null 2>&1; check "Required labels policy deployed" $?

echo ""
echo "--- Sample Application ---"
kubectl get deployment web-app -n app --context=production-cluster > /dev/null 2>&1; check "web-app deployed in production" $?
kubectl get pods -n app --context=production-cluster | grep -q Running; check "web-app pods running" $?
WEB_APP_SVC=$(kubectl get svc web-app -n app --context=production-cluster -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
check "web-app service exists" $([ -n "$WEB_APP_SVC" ] && echo 0 || echo 1)

echo ""
echo "--- Observability ---"
kubectl get statefulset prometheus -n monitoring --context=management-cluster > /dev/null 2>&1; check "Prometheus deployed" $?
kubectl get deployment thanos-query -n monitoring --context=management-cluster > /dev/null 2>&1; check "Thanos Query deployed" $?
kubectl get statefulset loki -n observability --context=management-cluster > /dev/null 2>&1; check "Loki deployed" $?
kubectl get deployment jaeger -n observability --context=management-cluster > /dev/null 2>&1; check "Jaeger deployed" $?

echo ""
echo "--- RBAC & Multi-tenancy ---"
kubectl get namespace team-alpha --context=production-cluster > /dev/null 2>&1; check "team-alpha namespace exists" $?
kubectl get namespace team-beta --context=production-cluster > /dev/null 2>&1; check "team-beta namespace exists" $?
kubectl get networkpolicies -n team-alpha --context=production-cluster | grep -q default-deny-all; check "Network policy: default-deny-all in team-alpha" $?

echo ""
echo "================================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "================================================"

[ "$FAIL" -eq "0" ] && exit 0 || exit 1
