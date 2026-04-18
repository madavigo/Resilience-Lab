output "server_id" {
  description = "OPNsense HAProxy server UUID"
  value       = opnsense_haproxy_server.this.id
}

output "backend_id" {
  description = "OPNsense HAProxy backend UUID"
  value       = opnsense_haproxy_backend.this.id
}

output "map_entry_id" {
  description = "OPNsense HAProxy map entry UUID"
  value       = opnsense_haproxy_mapfile_entry.this.id
}
