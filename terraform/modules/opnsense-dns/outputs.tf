output "host_ids" {
  description = "Map of hostname → OPNsense Unbound host UUID"
  value       = { for k, v in opnsense_unbound_host.hosts : k => v.id }
}
