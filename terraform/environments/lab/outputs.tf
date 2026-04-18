output "teleport_proxy_ip" {
  description = "Public IPv4 of the Teleport proxy VPS — add this as the 'teleport' A record in Cloudflare"
  value       = module.teleport_proxy.public_ipv4
}

output "cloudflare_zone_id" {
  description = "Cloudflare zone ID for madavigo.com"
  value       = module.cloudflare_zone.zone_id
}

output "vault_auth_backend_path" {
  description = "Mount path of the Vault Kubernetes auth backend"
  value       = module.vault_auth.auth_backend_path
}
