# Resilience-Lab — Cluster Recovery Runbook

## Scenario: NUC hardware failure (worst case)

### Step 1 — Replace hardware and boot Talos ISO

Boot the new NUC from the Talos v1.9.0 ISO (schematic `e9e068b5...`).
Verify it receives the DHCP reservation for `10.10.67.48`.

### Step 2 — Restore etcd from snapshot

```bash
# Option A: Get latest snapshot from TrueNAS NFS share
# Mount or access the NFS share from any machine on the network:
#   mount -t nfs 10.10.67.170:/mnt/SATA1/NFS/penguinhiding/resilience-lab /mnt/backup
#   ls /mnt/backup/etcd/  # find latest snapshot
#   cp /mnt/backup/etcd/etcd-snapshot-<TIMESTAMP>.db /tmp/restore.db

# Option B: Get snapshot from TrueNAS MinIO (Phase 2, if configured)
# mc alias set truenas <MINIO_ENDPOINT> <ACCESS_KEY> <SECRET_KEY> --insecure
# mc ls truenas/etcd-backups/ | sort | tail -1
# mc cp truenas/etcd-backups/etcd-snapshot-<TIMESTAMP>.db /tmp/restore.db

# Copy snapshot to local machine:
cp /path/to/etcd-snapshot-<TIMESTAMP>.db /tmp/restore.db

# Re-generate talos config or use existing secrets
talosctl gen config Resilience-Lab https://10.10.67.48:6443 \
  --with-secrets ./talos/secrets/secrets.yaml \
  --output-dir ./talos/generated

# Apply config and bootstrap from snapshot
talosctl apply-config --insecure \
  --nodes 10.10.67.48 \
  --file talos/generated/controlplane.yaml \
  --config-patch @talos/patches/nuc-patch.yaml

talosctl bootstrap \
  --nodes 10.10.67.48 \
  --recover-from /tmp/restore.db \
  --talosconfig talos/generated/talosconfig
```

### Step 3 — Re-join workers (if needed)

Workers maintain their state and will reconnect automatically once the
control plane API is back up. If any worker needs re-provisioning:

```bash
talosctl apply-config --insecure \
  --nodes <WORKER_IP> \
  --file talos/generated/worker.yaml \
  --config-patch @talos/patches/worker-storage-patch.yaml \
  --config-patch @talos/patches/worker-d0X-patch.yaml
```

### Step 4 — ArgoCD re-hydration

Once the cluster is healthy, re-apply the App-of-Apps.
ArgoCD will sync all applications from this repo automatically:

```bash
kubectl apply -f bootstrap/app-of-apps.yaml
```

All workloads, storage classes, and network policies are restored
from git within ~15 minutes.

### Step 5 — Unseal Vault

Vault requires manual unseal after pod restart. See `docs/vault-init-runbook.md`.

---

## Scenario: Worker node failure (d01, d02, or d03)

Ceph tolerates 1 OSD failure with 3x replication intact.

1. Replace hardware and boot Talos ISO
2. Apply config with `worker-storage-patch.yaml` + node overlay
3. Node joins cluster, Ceph auto-rebalances OSDs - no data loss

### Zapping a Ceph OSD disk

If a replacement disk (or reused disk) has stale LVM/Ceph/bluestore metadata,
Rook will refuse to provision an OSD on it. You must zap the disk first.

**Symptoms:**
- OSD prepare job never runs for the node
- `talosctl get discoveredvolumes` shows `lvm2-pv` or `bluestore` labels on the disk
- Operator logs show only 2 of 3 failure domains

**Fix:** Deploy a privileged pod on the affected node to wipe the disk:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: disk-zap-<NODE>
  namespace: rook-ceph
spec:
  restartPolicy: Never
  nodeName: resilience-<NODE>
  containers:
    - name: disk-zap
      image: quay.io/ceph/ceph:v18.2.0
      command: ["/bin/bash", "-c"]
      args:
        - |
          set -ex
          sgdisk --zap-all /dev/sda
          dd if=/dev/zero of=/dev/sda bs=1M count=100
          wipefs -af /dev/sda
          dd if=/dev/zero of=/dev/sda bs=1M count=100 seek=400
          ls /dev/mapper/ceph-* 2>/dev/null && dmsetup remove_all || true
          rm -rf /dev/ceph-*
          echo "Disk fully zapped"
      securityContext:
        privileged: true
      volumeMounts:
        - name: dev
          mountPath: /dev
  volumes:
    - name: dev
      hostPath:
        path: /dev
EOF
```

After the pod completes, clean up and restart the operator:

```bash
kubectl delete pod -n rook-ceph disk-zap-<NODE>
kubectl delete pod -n rook-ceph -l app=rook-ceph-operator
```

The operator will rescan disks and provision the OSD automatically.
