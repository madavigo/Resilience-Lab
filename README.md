# Resilience-Lab (ProjPho)

**What is it?** it's a production-grade, bare-metal Kubernetes reference architecture. It serves as a living portfolio for modern Platform Engineering, demonstrating high-availability, distributed storage, and automated disaster recovery.

## The Mission
To architect a cluster that is entirely "expendable." Utilizing **Talos OS**, the cluster can be rebuilt from a clean state in under 15 minutes. It is a dual-purpose environment:
1. **The Laboratory:** A sandbox for SRE/Platform engineering experiments.
2. **The Provider:** A commercial Akash Network node providing compute and storage (Rook-Ceph) to the decentralized marketplace.

## 🛠 Tech Stack
- **OS:** [Talos Linux](https://www.talos.dev/) (API-driven, Immutable, Security-hardened)
- **CRI:** [k3s](https://k3s.io/) / K8s (Using Image Optimized for 1L Dell Micros and NUC 11)
- **Storage:** [Rook-Ceph](https://rook.io/) (Distributed Block/Object storage on Intel DC SSDs)
- **Networking:** Multi-Fabric (1GbE Management / 2.5GbE Storage Replication)
- **GitOps:** [ArgoCD](https://argoproj.github.io/cd/) (Continuous Delivery)
- **Secrets:** [External Secrets Operator](https://external-secrets.io/) + Vault (Zero Trust Posture)
- **Observability:** Prometheus, Grafana, & Loki (Full-stack monitoring)

## 🏗 Network Architecture
- **Control Plane:** Hosted on Intel NUC 11 (High-performance single-master with automated `etcd` snapshots).
- **Compute Plane:** 3-6x Dell Micro nodes (i5-6500T, 64GB RAM).
- **Storage Plane:** Dedicated 2.5GbE fabric with MTU 9000 (Jumbo Frames) for Ceph OSD replication.
- **Tenant Isolation:** Public-facing Akash workloads isolated via VLAN and NetworkPolicies.

## 🛡 Security & Zero Trust
This repository is 100% public-ready.
- **No Secrets:** All sensitive credentials are managed via the External Secrets Operator.
- **API Management:** All node interaction occurs via the Talos API (No SSH).
- **Backups:** Multi-tier backups via Velero and `etcd` snapshots to S3 (TrueNAS MinIO).
