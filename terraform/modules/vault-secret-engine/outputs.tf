output "mount_path" {
  description = "Path where the KV v2 engine is mounted"
  value       = vault_mount.kv.path
}

output "mount_accessor" {
  description = "Accessor of the KV mount (useful for identity policies)"
  value       = vault_mount.kv.accessor
}

output "policy_names" {
  description = "List of policy names created by this module"
  value       = keys(vault_policy.policies)
}
