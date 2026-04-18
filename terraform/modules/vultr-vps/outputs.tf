output "instance_id" {
  description = "Vultr instance UUID"
  value       = vultr_instance.this.id
}

output "public_ipv4" {
  description = "Primary public IPv4 address of the instance"
  value       = vultr_instance.this.main_ip
}

output "hostname" {
  description = "FQDN of the instance (passed through from variable)"
  value       = var.hostname
}

output "firewall_group_id" {
  description = "UUID of the firewall group attached to this instance"
  value       = vultr_firewall_group.this.id
}
