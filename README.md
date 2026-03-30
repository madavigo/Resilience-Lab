# Resilience-Lab

**A production-grade, bare-metal Kubernetes reference architecture.** A living portfolio for modern Platform Engineering, demonstrating high-availability, distributed storage, and automated disaster recovery on commodity hardware.

## Cluster Status

| Component | Status | Details |
|-----------|--------|---------|
| Control Plane (NUC) | LIVE | Talos v1.9.0, booting from NVMe |
| Worker d01 | LIVE | Talos v1.9.0, Ceph storage node |
| Worker d02 | LIVE | Talos v1.9.0, Ceph storage node |
| Worker d03 | LIVE | Talos v1.9.0, Ceph storage node |
| etcd Backup | LIVE | CronJob every 4h to TrueNAS NFS |
| etcd DR Restore | TESTED | Full destructive restore validated 2026-03-18 |
| Rook-Ceph | LIVE | 3 OSDs on Intel DC SSDs, ceph-block StorageClass |
| ArgoCD / GitOps | LIVE | App-of-Apps pattern, ingress at argocd.madavigo.com |
| MetalLB | LIVE | BGP peering with OPNsense (AS 64512/64513) |
| ingress-nginx | LIVE | TLS via cert-manager + Let's Encrypt (Cloudflare DNS-01) |
| Democratic-CSI | LIVE | TrueNAS NFS provisioner, truenas-nfs StorageClass |
| Vault / ESO | LIVE | Secret pipeline operational, vault.madavigo.com |
| Authentik | LIVE | SSO/MFA, forward auth on Ceph dashboard |
| Grafana | LIVE | OIDC via Authentik, grafana.madavigo.com |
| Prometheus | LIVE | kube-prometheus-stack on truenas-nfs |
| Loki | LIVE | Log aggregation with Alloy collectors |
| Velero | LIVE | Daily PVC backups to TrueNAS MinIO (14-day retention) |

## Hardware Inventory

| Hostname | Role | Hardware | IP |
|----------|------|----------|----|
| resilience-nuc | Control Plane | Intel NUC 11 (i7, 16GB RAM, 1TB NVMe) | 10.10.67.48 |
| resilience-d01 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.40 |
| resilience-d02 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.41 |
| resilience-d03 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.42 |
| TrueNAS | NFS / MinIO backend | - | 10.10.67.170 |

## The Mission

To architect a cluster that is entirely "expendable." Utilizing **Talos OS**, the cluster can be rebuilt from a clean state in under 15 minutes. It is a dual-purpose environment:

1. **The Laboratory:** A sandbox for SRE/Platform engineering experiments.
2. **The Provider:** A Rook-Ceph backed storage and compute platform for distributed workloads.

## Tech Stack

- **OS:** [Talos Linux v1.9.0](https://www.talos.dev/) - API-driven, immutable, no SSH
- **Orchestration:** Kubernetes v1.32.0
- **Storage:** [Rook-Ceph](https://rook.io/) - Distributed block/object on Intel DC SSDs
- **Networking:** Dual-fabric (1GbE management / 2.5GbE Ceph replication, MTU 9000)
- **GitOps:** [ArgoCD](https://argoproj.github.io/cd/) - Continuous delivery
- **Secrets:** [External Secrets Operator](https://external-secrets.io/) + Vault - Zero secrets in git
- **Observability:** Prometheus, Grafana, Loki - Full-stack monitoring
- **Backup:** etcd snapshots to TrueNAS NFS + Velero PVC backups

## Network Architecture

- **Control Plane:** Intel NUC 11 - single-master with automated etcd snapshots every 4 hours.
- **Compute Plane:** 3x Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM).
- **Storage Plane:** Dedicated 2.5GbE fabric with MTU 9000 (Jumbo Frames) for Ceph OSD replication.

## Disaster Recovery

### Three-Tier Backup Strategy

| Tier | Method | Target | Schedule | Retention |
|------|--------|--------|----------|-----------|
| 1 | etcd snapshots (CronJob) | TrueNAS NFS | Every 4 hours | 7 days |
| 2 | ArgoCD GitOps re-hydration | This repo | On demand | Infinite (git history) |
| 3 | Velero PVC backups | TrueNAS MinIO | Daily at 2am | 14 days |

### DR Test Results - 2026-03-18

**Scenario:** Full control plane destruction and recovery from etcd snapshot.

**Procedure:**
1. Took etcd snapshot via automated CronJob, verified on TrueNAS NFS (2.1 MB, 1236 keys, revision 20723)
2. Validated snapshot integrity with `etcdutl snapshot status` - hash, revision, and key count all matched
3. Wiped control plane with `talosctl reset --graceful=false` - NUC NVMe fully destroyed
4. Booted NUC from Talos USB ISO, re-applied control plane config
5. Bootstrapped etcd from snapshot: `talosctl bootstrap --recover-from /tmp/restore.db`
6. Ran `talosctl upgrade --preserve` to reinstall to NVMe
7. Pulled USB - NUC booted from NVMe with restored state

**Results:**
- PASS: All 3 worker nodes (d01-d03) auto-rejoined without intervention
- PASS: All namespaces, RBAC, and workload definitions restored
- PASS: etcd-backup CronJob itself was restored and fired on schedule
- PASS: Total recovery time: ~10 minutes (manual process)

### Recovery Runbook

See [`docs/recovery-runbook.md`](docs/recovery-runbook.md) for step-by-step instructions.

## Security & Zero Trust

This repository is 100% public-ready.
- **No Secrets:** All credentials managed via External Secrets Operator + Vault.
- **API Management:** All node interaction via Talos API - no SSH anywhere.
- **Immutable OS:** Talos Linux has no shell, no package manager, no writable rootfs.

## Repo Structure

```
talos/patches/          Talos machine config patches (shared + per-node)
talos/generated/        Generated configs (not committed, use secrets.yaml to regenerate)
bootstrap/              One-time ArgoCD install + App-of-Apps
apps/platform/          argocd, ingress-nginx, cert-manager
apps/infrastructure/    rook-ceph, democratic-csi, vault, external-secrets,
                        etcd-backup, velero, network-policies
apps/observability/     kube-prometheus-stack, loki
docs/                   vault-init-runbook, recovery-runbook
```
