# Terraform — Resilience Lab IaC

Manages all external infrastructure that lives **outside** Kubernetes: Cloudflare DNS, OPNsense HAProxy + Unbound, Vultr VPS instances, and HashiCorp Vault configuration (auth methods, secret engines, policies). Kubernetes workloads are managed by ArgoCD; Terraform handles everything upstream of the cluster.

---

## Hybrid Architecture

The Resilience Lab is not a pure cloud environment or a pure homelab — it is deliberately **hybrid**:

```
Internet
    │
    ├─── Cloudflare (DNS + proxy)
    │        Public A records for music, emby/s, teleport
    │        Proxied traffic → OPNsense HAProxy
    │
    └─── Vultr DFW VPS
             Teleport proxy tier (public-facing)
             Reverse tunnel ← cluster on port 3024
             Toothy SSH access to TrueNAS audited via Teleport

LAN (10.10.67.0/24)
    │
    ├─── OPNsense (10.10.67.1) — firewall / router
    │        HAProxy → routes by hostname to cluster or TrueNAS
    │        Unbound → local DNS for all *.madavigo.com subdomains
    │
    ├─── MetalLB (10.10.70.0) — Kubernetes ingress VIP
    │        ingress-nginx terminates TLS (cert-manager + Let's Encrypt)
    │
    ├─── Kubernetes cluster (10.10.67.40-48)
    │        Apps managed by ArgoCD from git.madavigo.com
    │
    └─── TrueNAS (10.10.67.170)
             NFS StorageClass (democratic-csi)
             MinIO (Velero backups, Terraform state)
             Gitea (self-hosted, LAN-only)
```

### Traffic path for a public service (e.g., `music.madavigo.com`)

```
Browser → Cloudflare (proxied) → OPNsense HAProxy (SNI passthrough)
    → MetalLB 10.10.70.0 → ingress-nginx → Navidrome pod
```

### Traffic path for a LAN-only service (e.g., `argocd.madavigo.com`)

```
LAN client → OPNsense Unbound (resolves to 10.10.67.1) → OPNsense HAProxy (LOCAL map)
    → MetalLB 10.10.70.0 → ingress-nginx → ArgoCD pod
    (not reachable from internet — no Cloudflare record, blocked at OPNsense)
```

### Teleport zero-trust access

The Teleport auth and node tiers run inside the cluster. The proxy tier runs on a Vultr VPS so the home WAN IP never appears in DNS or firewall rules:

```
Operator → teleport.madavigo.com (Vultr DFW, not Cloudflare-proxied, direct TCP)
    → Teleport proxy VPS → reverse tunnel (port 3024) → cluster auth tier
    → kubectl sessions, TrueNAS SSH — all audited
```

---

## Module Inventory

| Module | Manages | Provider |
|---|---|---|
| `cloudflare-zone` | DNS A/CNAME records for madavigo.com | Cloudflare |
| `vault-auth` | Kubernetes auth backend + ESO role | Vault |
| `vault-secret-engine` | KV v2 mount + access policies | Vault |
| `vultr-vps` | VPS instances with cloud-init + firewall rules | Vultr |
| `opnsense-service` | HAProxy server + backend + map file entry | OPNsense |
| `opnsense-dns` | Unbound host override entries | OPNsense |

### `opnsense-service` exposure model

The `type` parameter controls which HAProxy map and TLS mode is used. **Default is `local`** — you must explicitly opt-in to public exposure.

| type | HAProxy map | TLS | Reachable from |
|---|---|---|---|
| `local` | LOCAL_SUBDOMAINS | plain HTTP | LAN only |
| `local-ssl` | LOCAL_SUBDOMAINS | SSL verify none | LAN only |
| `local-nooffload` | LOCAL_NOOFFLOAD | SNI passthrough | LAN only |
| `cluster-public` | PUBLIC_SUBDOMAINS | SNI passthrough to MetalLB | Internet |
| `public` | PUBLIC_SUBDOMAINS | plain HTTP to target | Internet |
| `public-ssl` | PUBLIC_SUBDOMAINS | SSL verify none | Internet |

---

## Structure

```
terraform/
├── modules/
│   ├── cloudflare-zone/        DNS record management via Cloudflare provider
│   ├── vault-auth/             Vault Kubernetes auth backend + roles
│   ├── vault-secret-engine/    Vault KV v2 mount + policies
│   ├── vultr-vps/              Vultr VPS with cloud-init and firewall rules
│   │   └── cloud-init/
│   │       └── teleport-proxy.yaml.tpl   Cloud-init template for Teleport proxy
│   ├── opnsense-service/       OPNsense HAProxy server + backend + map entry
│   └── opnsense-dns/           OPNsense Unbound host overrides
├── environments/
│   ├── lab/                    Live lab environment (madavigo.com)
│   └── _template/              Copy this to add a new environment
└── README.md
```

### Why directory-per-environment, not workspaces

Terraform workspaces share a single backend config and codebase — they are designed for identical infrastructure deployed to multiple targets. When environments differ structurally (different modules, different record sets), directory separation is cleaner:

- Each environment owns its `backend.tf` with a unique state key.
- State files are isolated — a `terraform destroy` in `lab/` cannot touch another environment.
- `main.tf` can call a different set of modules per environment without variable gymnastics.
- This is the pattern Terragrunt enforces; understanding it demonstrates deeper Terraform knowledge.

---

## Remote State: MinIO S3 Backend

State is stored in MinIO (TrueNAS) using the S3-compatible backend. The `backend "s3"` block is identical to a real AWS S3 backend — the only differences are three `skip_*` flags and `force_path_style = true` required for non-AWS endpoints.

State bucket: `terraform-state` on `minio.madavigo.com`
State key per environment: `<env-name>/terraform.tfstate`

---

## Quickstart

### Prerequisites

- Terraform >= 1.6 (`brew install terraform`)
- MinIO bucket `terraform-state` created (one-time, manual)
- Cloudflare API token with `Zone:Edit` for `madavigo.com`
- Vault token with permissions to manage auth/mount/policy resources
- OPNsense API key + secret with HAProxy and DNS write permissions
- Vultr API key

### Initialize

```bash
cd terraform/environments/lab

export AWS_ACCESS_KEY_ID=<minio-access-key>
export AWS_SECRET_ACCESS_KEY=<minio-secret-key>
export TF_VAR_cloudflare_api_token=<cloudflare-token>
export TF_VAR_vault_token=<vault-token>
export TF_VAR_opnsense_api_key=<opnsense-key>
export TF_VAR_opnsense_api_secret=<opnsense-secret>
export TF_VAR_vultr_api_key=<vultr-key>
export TF_VAR_kubernetes_ca_cert="$(kubectl --kubeconfig ~/.kube/config-resilience-lab \
  config view --raw --minify \
  --output 'jsonpath={.clusters[0].cluster.certificate-authority-data}' | base64 -d)"

terraform init
```

### Plan and apply

```bash
terraform plan
terraform apply
```

### First apply — import existing resources

OPNsense HAProxy objects and DNS entries may already exist in the UI. Import them before `apply` to avoid duplicates:

> **State lock:** Always run `terraform import` from a single terminal session. The MinIO S3 backend acquires a state lock for every write. If a previous run was interrupted and the lock was not released, use `terraform force-unlock <LOCK_ID>` — but only after confirming no other `apply` or `import` is in progress. The lock ID is printed when the lock is acquired and is also visible in the MinIO bucket as a `.tflock` object.

```bash
# HAProxy server, backend, and map entry for each service:
terraform import module.haproxy_<name>.opnsense_haproxy_server.this <server-uuid>
terraform import module.haproxy_<name>.opnsense_haproxy_backend.this <backend-uuid>
terraform import module.haproxy_<name>.opnsense_haproxy_mapfile_entry.this <entry-uuid>

# UUIDs are visible in OPNsense UI URLs or via API:
curl -s -u "<key>:<secret>" \
  https://opnsense.madavigo.com/api/haproxy/server/searchServer \
  | jq '.rows[] | {name: .name, uuid: .uuid}'
```

---

## How to Add a New Service

### LAN-only cluster service (most services)

1. Add a `module "haproxy_<name>"` block in `environments/lab/main.tf` with `type = "local"` and `target_ip = "10.10.70.0"`.
2. Add a host entry to `module "opnsense_dns"` pointing to `10.10.70.0` (routes through HAProxy LOCAL map).
3. Run `terraform apply -target=module.haproxy_<name> -target=module.opnsense_dns`.

### Making an existing LAN service public

1. Change `type` from `"local"` to `"cluster-public"` in the `haproxy_<name>` module.
2. Add a proxied Cloudflare `A` record pointing to `10.10.70.0` in `module "cloudflare_zone"`.
3. Run `terraform apply`.

### Adding a new environment

```bash
cp -r terraform/environments/_template terraform/environments/<env-name>
# Edit backend.tf: set key = "<env-name>/terraform.tfstate"
# Edit terraform.tfvars with environment-specific defaults
terraform init
```

---

## Sensitive Values

Never commit secrets to this repo. All sensitive variables (`cloudflare_api_token`, `vault_token`, `opnsense_api_key`, `opnsense_api_secret`, `vultr_api_key`, `kubernetes_ca_cert`) must be passed via `TF_VAR_*` environment variables or a local `terraform.tfvars.local` file (gitignored).

The `terraform.tfvars` files committed to this repo contain only non-sensitive defaults (URLs, region names, plan slugs). Treat any file named `*.tfvars.local` as a secret — it is in `.gitignore`.

---

## State File

After first `apply`, verify state exists in MinIO:

```
terraform-state/
└── lab/
    └── terraform.tfstate
```

A second `terraform apply` with no infrastructure changes should produce:

```
No changes. Your infrastructure matches the configuration.
```

---

## Scaffolded — Not Yet Applied

The `lab` environment is **scaffolded** — the code is complete and has been reviewed, but `terraform init && terraform apply` has not been run against the live environment yet. The HAProxy and DNS entries currently exist as manually configured objects in OPNsense.

**To bring Terraform into control of the live environment:**

1. Collect UUIDs of all existing HAProxy objects and Unbound entries.
2. Run `terraform import` for each object (see "First apply" above).
3. Run `terraform plan` — should show zero changes after all imports complete.
4. Commit the state file path (it lives in MinIO, not in git) and proceed with normal `plan/apply` workflow.
