output "auth_backend_path" {
  description = "Mount path of the Kubernetes auth backend"
  value       = vault_auth_backend.kubernetes.path
}

output "role_name" {
  description = "Name of the Vault auth role"
  value       = vault_kubernetes_auth_backend_role.role.role_name
}
