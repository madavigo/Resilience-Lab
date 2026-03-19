# Vault Init Runbook

Vault requires a one-time manual initialization after first deploy.
All subsequent operations are automated via External Secrets Operator.

## Step 1 — Initialize Vault

```bash
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > vault-init.json

# STORE vault-init.json SECURELY (offline / password manager).
# This file contains unseal keys and the root token. NEVER commit it.
```

## Step 2 — Unseal Vault (run after every pod restart)

```bash
# Provide 3 of the 5 unseal keys
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_1>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_2>
kubectl exec -n vault vault-0 -- vault operator unseal <KEY_3>
```

> **Production hardening:** Replace manual unseal with [Vault Auto Unseal](https://developer.hashicorp.com/vault/docs/configuration/seal) using a cloud KMS or TPM once the lab evolves.

## Step 3 — Enable KV v2 and Seed Secrets

```bash
export VAULT_ADDR=https://vault.lab.local   # or port-forward: kubectl port-forward svc/vault -n vault 8200:8200
export VAULT_TOKEN=<root-token-from-vault-init.json>

vault secrets enable -path=secret kv-v2

# TrueNAS API credentials (used by democratic-csi)
vault kv put secret/resilience-lab/truenas \
  username="<truenas-api-user>" \
  password="<truenas-api-key>"

# Akash wallet mnemonic (used by Akash Provider)
vault kv put secret/resilience-lab/akash \
  mnemonic="<24-word BIP39 mnemonic>"

# ArgoCD GitHub repo access (if repo goes private)
vault kv put secret/resilience-lab/github \
  token="<github-pat>"
```

## Step 4 — Create ESO Service Account Token

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

vault policy write eso-policy - <<EOF
path "secret/data/resilience-lab/*" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/eso-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-policy \
  ttl=24h
```

## Step 5 — Bootstrap ESO Token Secret

```bash
# One-time bootstrap — after this, ESO rotates its own access
kubectl create secret generic vault-token \
  -n external-secrets \
  --from-literal=token="<root-token>"
```
