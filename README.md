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
| Rook-Ceph | PENDING | Hardware ready, deployment next |
| ArgoCD / GitOps | PENDING | Bootstrap manifests in repo |
| Vault / ESO | PENDING | Runbook drafted |
| Observability | PENDING | Prometheus + Grafana + Loki |

## Hardware Inventory

| Hostname | Role | Hardware | IP |
|----------|------|----------|----|
| resilience-nuc | Control Plane | Intel NUC 11 (i7, 64GB RAM, 1TB NVMe) | 10.10.67.48 |
| resilience-d01 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.40 |
| resilience-d02 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.41 |
| resilience-d03 | Worker (Ceph) | Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM, NVMe + 480GB Intel DC SSD) | 10.10.67.42 |
| resilience-d04-d06 | Workers (Ephemeral) | Dell OptiPlex 7040 Micro | 10.10.67.43-45 |
| TrueNAS | NFS / MinIO backend | - | 10.10.67.170 |

## The Mission

To architect a cluster that is entirely "expendable." Utilizing **Talos OS**, the cluster can be rebuilt from a clean state in under 15 minutes. It is a dual-purpose environment:

1. **The Laboratory:** A sandbox for SRE/Platform engineering experiments.
2. **The Provider:** A commercial Akash Network node providing compute and storage (Rook-Ceph) to the decentralized marketplace.

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
- **Compute Plane:** 3-6x Dell OptiPlex 7040 Micro (i5-6500T, 64GB RAM).
- **Storage Plane:** Dedicated 2.5GbE fabric with MTU 9000 (Jumbo Frames) for Ceph OSD replication.
- **Tenant Isolation:** Public-facing Akash workloads isolated via VLAN 700 and NetworkPolicies.

## Disaster Recovery

### Three-Tier Backup Strategy

| Tier | Method | Target | Schedule | Retention |
|------|--------|--------|----------|-----------|
| 1 | etcd snapshots (CronJob) | TrueNAS NFS | Every 4 hours | 7 days |
| 2 | ArgoCD GitOps re-hydration | This repo | On demand | Infinite (git history) |
| 3 | Velero PVC backups | TrueNAS MinIO | Daily (planned) | 14 days |

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
apps/akash/             provider + wallet ExternalSecret
docs/                   vault-init-runbook, recovery-runbook
```
