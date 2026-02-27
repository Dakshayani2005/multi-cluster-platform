# Runbook: Disaster Recovery — etcd and Persistent Volume Backup

**Category:** Disaster Recovery  
**Last Updated:** 2025-01-01  
**Owner:** Platform Engineering Team  
**RTO:** 2 hours | **RPO:** 24 hours

---

## Overview

This runbook documents the automated backup strategy for cluster state (etcd) and application data (persistent volumes), and provides step-by-step restoration procedures.

---

## Backup Strategy

### etcd (Cluster State)

EKS manages the etcd control plane. AWS automatically backs it up. For self-managed clusters:

```bash
# Manual etcd snapshot (if self-managed)
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Upload to S3
aws s3 cp /backup/etcd-snapshot-$(date +%Y%m%d).db s3://multi-cluster-backups/etcd/
```

### Persistent Volumes (Application Data)

Velero handles automated PV snapshots:

```bash
# Install Velero (run once during cluster setup)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.9.0 \
  --bucket multi-cluster-velero-backups \
  --backup-location-config region=us-east-1 \
  --use-volume-snapshots=true \
  --secret-file ./velero-credentials

# Scheduled daily backup at 2am UTC
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces=app,database,team-alpha,team-beta \
  --ttl 720h   # 30-day retention
```

---

## Restoration Procedures

### Restore from Velero Backup

```bash
# List available backups
velero backup get

# Restore a specific backup
velero restore create --from-backup daily-backup-20250101020000

# Monitor restore progress
velero restore describe <restore-name> --details

# Verify pods are running after restore
kubectl get pods -n app
kubectl get pods -n database
```

### Full Cluster Rebuild (Catastrophic Failure)

```bash
# 1. Re-provision infrastructure
cd infra/terraform/production
terraform init && terraform apply -auto-approve

# 2. Update kubeconfig
aws eks update-kubeconfig --name production-cluster --region eu-west-1

# 3. Re-install Velero
velero install [same flags as above]

# 4. Restore from latest backup
LATEST_BACKUP=$(velero backup get --output json | jq -r '.items | sort_by(.metadata.creationTimestamp) | last | .metadata.name')
velero restore create --from-backup ${LATEST_BACKUP}

# 5. Re-register cluster with ArgoCD
argocd cluster add production-cluster

# 6. ArgoCD re-syncs all platform components automatically
argocd app sync platform-root
```

---

## Recovery Verification Checklist

```bash
# All pods running
kubectl get pods -A | grep -v Running | grep -v Completed

# All PVCs bound
kubectl get pvc -A | grep -v Bound

# Database data intact
kubectl exec -n database statefulset/postgres -- psql -U appuser -d appdb -c "SELECT count(*) FROM your_table;"

# Istio mesh healthy
istioctl proxy-status

# ArgoCD all apps synced
argocd app list | grep -v Synced

# Observability working
curl http://thanos-query.monitoring.svc.cluster.local:9090/-/ready
curl http://loki.observability.svc.cluster.local:3100/ready
```
