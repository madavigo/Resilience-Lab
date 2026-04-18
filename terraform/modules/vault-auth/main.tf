terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

# Enable the Kubernetes auth method at the default path.
# If auth/kubernetes already exists (e.g. manually enabled), use terraform import:
#   terraform import vault_auth_backend.kubernetes auth/kubernetes
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
}

resource "vault_kubernetes_auth_backend_config" "config" {
  backend            = vault_auth_backend.kubernetes.path
  kubernetes_host    = var.kubernetes_host
  kubernetes_ca_cert = var.kubernetes_ca_cert

  # When Vault runs inside the cluster it can use the pod's service account
  # token for token review. Disable_local_ca_jwt = false (default) uses the
  # pod's projected token which works for in-cluster Vault deployments.
  disable_local_ca_jwt = false
}

resource "vault_kubernetes_auth_backend_role" "role" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = var.vault_role_name
  bound_service_account_names      = [var.service_account_name]
  bound_service_account_namespaces = concat([var.service_account_namespace], var.bound_namespaces)
  token_policies                   = var.vault_policies
  token_ttl                        = var.token_ttl
  token_max_ttl                    = var.token_max_ttl

  depends_on = [vault_kubernetes_auth_backend_config.config]
}
