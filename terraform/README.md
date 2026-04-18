# Terraform — Resilience Lab IaC

Manages external infrastructure that lives outside Kubernetes: Cloudflare DNS records and HashiCorp Vault configuration (auth methods, secret engines, policies). Kubernetes workloads are managed by ArgoCD; Terraform handles everything upstream of the cluster.

## Structure

```
terraform/
├── modules/
│   ├── cloudflare-zone/        # DNS record management via Cloudflare provider
│   ├── vault-auth/             # Vault Kubernetes auth backend + roles
│   └── vault-secret-engine/    # Vault KV v2 mount + policies
├── environments/
│   ├── lab/                    # Live lab environment (madavigo.com)
│   └── _template/              # Copy this to add a new environment
└── README.md
```

### Why directory-per-environment, not workspaces

Terraform workspaces share a single backend config and codebase — they're designed for identical infrastructure deployed to multiple targets (e.g., n copies of the same app stack). When environments differ structurally (different modules, different providers, different record sets), directory separation is cleaner:

- Each environment owns its `backend.tf` with a unique state key
- State files are isolated — a `terraform destroy` in `lab/` cannot touch another environment
- `main.tf` can call a different set of modules per environment without variable gymnastics
- This is the pattern Terragrunt enforces; understanding it demonstrates deeper Terraform knowledge

### Why these modules

| Module | What it manages | Provider interaction |
|---|---|---|
| `cloudflare-zone` | DNS A/CNAME records for madavigo.com | Cloudflare REST API via API token |
| `vault-auth` | Kubernetes auth backend + ESO role | Vault API — auth method lifecycle |
| `vault-secret-engine` | KV v2 mount + access policies | Vault API — mount + policy lifecycle |

All three integrate with systems already running in the lab, so `terraform plan` shows real drift and `terraform apply` has observable effects.

## Remote State: MinIO S3 Backend

State is stored in MinIO (TrueNAS) using the S3-compatible backend. The `backend "s3"` block is identical to a real AWS S3 backend — the only differences are three `skip_*` flags and `force_path_style = true` required for non-AWS endpoints. Remove those flags, point `endpoint` at `s3.amazonaws.com`, and it works against AWS unchanged.

State bucket: `terraform-state` on `minio.madavigo.com`  
State key per environment: `<env-name>/terraform.tfstate`

## Quickstart

### Prerequisites

- Terraform >= 1.6 (`brew install terraform`)
- MinIO bucket `terraform-state` created (one-time, manual)
- Cloudflare API token with `Zone:Edit` for `madavigo.com`
- Vault token with permissions to manage auth/mount/policy resources

### Initialize

```bash
cd terraform/environments/lab

export AWS_ACCESS_KEY_ID=<minio-access-key>
export AWS_SECRET_ACCESS_KEY=<minio-secret-key>
export TF_VAR_cloudflare_api_token=<cloudflare-token>
export TF_VAR_vault_token=<vault-token>
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

### Adding a new environment

```bash
cp -r terraform/environments/_template terraform/environments/<env-name>
# Edit backend.tf: set key = "<env-name>/terraform.tfstate"
# Edit terraform.tfvars with environment-specific defaults
# Run terraform init in the new directory
```

## State file location

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

## Sensitive values

Never commit secrets to this repo. All sensitive variables (`cloudflare_api_token`, `vault_token`, `kubernetes_ca_cert`) must be passed via `TF_VAR_*` environment variables or a local `terraform.tfvars.local` file (gitignored).
