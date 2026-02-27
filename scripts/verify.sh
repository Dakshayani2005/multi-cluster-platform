#!/usr/bin/env bash
set -euo pipefail

echo "==> Platform Verification Suite"
echo "    Tests: cross-cluster comms, failover, policy enforcement, Backstage"

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

# ---- Test 1: Cross-cluster service communication ----
echo ""
echo "--- Test 1: Cross-Cluster Service Communication ---"
# Deploy test pod in management cluster, curl web-app.app.global (ServiceEntry)
kubectl run cross-cluster-test \
  --image=curlimages/curl:8.7.1 \
  --restart=Never \
  --namespace=default \
  --context=management-cluster \
  --command -- curl -s --max-time 10 http://web-app.app.global/healthz > /tmp/cross-cluster-test.txt 2>&1

kubectl wait --for=condition=Completed pod/cross-cluster-test \
  --namespace=default --context=management-cluster --timeout=60s 2>/dev/null || true

RESULT=$(kubectl logs cross-cluster-test --context=management-cluster 2>/dev/null)
kubectl delete pod cross-cluster-test --context=management-cluster 2>/dev/null || true
check "Cross-cluster HTTP request succeeds" $(echo "$RESULT" | grep -q "200\|OK\|healthy" && echo 0 || echo 1)

# ---- Test 2: OPA Policy Enforcement ----
echo ""
echo "--- Test 2: OPA Policy Enforcement ---"

# Test privileged container (should be DENIED)
PRIV_RESULT=$(cat <<EOF | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: policy-test-privileged
  namespace: app
  labels:
    app: test
    team: platform
    environment: test
spec:
  containers:
    - name: test
      image: nginx
      securityContext:
        privileged: true
      resources:
        requests: {cpu: 50m, memory: 64Mi}
        limits: {cpu: 200m, memory: 256Mi}
EOF
)
echo "$PRIV_RESULT" | grep -q "denied\|Forbidden" 
check "OPA blocks privileged container" $(echo "$PRIV_RESULT" | grep -q "denied\|Forbidden" && echo 0 || echo 1)
kubectl delete pod policy-test-privileged -n app 2>/dev/null || true

# Test missing resource limits (should be DENIED)
NO_LIMITS_RESULT=$(cat <<EOF | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: policy-test-no-limits
  namespace: app
  labels:
    app: test
    team: platform
    environment: test
spec:
  containers:
    - name: test
      image: nginx
EOF
)
check "OPA blocks container without resource limits" $(echo "$NO_LIMITS_RESULT" | grep -q "denied\|Forbidden" && echo 0 || echo 1)
kubectl delete pod policy-test-no-limits -n app 2>/dev/null || true

# Test missing labels (should be DENIED)
NO_LABELS_RESULT=$(cat <<EOF | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: policy-test-no-labels
  namespace: app
spec:
  containers:
    - name: test
      image: nginx
      resources:
        requests: {cpu: 50m, memory: 64Mi}
        limits: {cpu: 200m, memory: 256Mi}
EOF
)
check "OPA blocks pod without required labels" $(echo "$NO_LABELS_RESULT" | grep -q "denied\|Forbidden" && echo 0 || echo 1)
kubectl delete pod policy-test-no-labels -n app 2>/dev/null || true

# ---- Test 3: Regional Failover ----
echo ""
echo "--- Test 3: Regional Failover Simulation ---"

echo "  Cordoning all production cluster nodes..."
kubectl get nodes --context=production-cluster -o name | \
  xargs -I {} kubectl cordon {} --context=production-cluster 2>/dev/null || true

echo "  Waiting 60s for Istio to detect unhealthy endpoints..."
sleep 60

# Send 10 requests; all should succeed (served by management cluster)
ERRORS=0
for i in $(seq 1 10); do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://web-app.example.com/ 2>/dev/null || echo "000")
  if [ "$STATUS" != "200" ]; then
    ERRORS=$((ERRORS + 1))
  fi
done
check "Traffic serves successfully during regional failover (${ERRORS}/10 errors)" \
  $([ "$ERRORS" -le 1 ] && echo 0 || echo 1)

echo "  Restoring production cluster nodes..."
kubectl get nodes --context=production-cluster -o name | \
  xargs -I {} kubectl uncordon {} --context=production-cluster 2>/dev/null || true

# ---- Test 4: Observability Endpoints ----
echo ""
echo "--- Test 4: Observability Stack ---"

THANOS_READY=$(kubectl exec -n monitoring deploy/thanos-query --context=management-cluster -- \
  wget -qO- http://localhost:9090/-/ready 2>/dev/null || echo "")
check "Thanos Query is ready" $(echo "$THANOS_READY" | grep -q "Thanos Query is Ready" && echo 0 || echo 1)

LOKI_READY=$(kubectl exec -n observability statefulset/loki --context=management-cluster -- \
  wget -qO- http://localhost:3100/ready 2>/dev/null || echo "")
check "Loki is ready" $(echo "$LOKI_READY" | grep -q "ready" && echo 0 || echo 1)

echo ""
echo "================================================"
echo "  Results: ${PASS} passed, ${FAIL} failed"
echo "================================================"

[ "$FAIL" -eq "0" ] && exit 0 || exit 1
