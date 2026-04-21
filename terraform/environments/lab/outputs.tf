output "proxy_ip" {
  description = "Public IPv4 of the front-proxy VPS (HAProxy + WireGuard). All *.madavigo.com Cloudflare A records point here."
  value       = module.proxy.public_ipv4
}

output "cloudflare_zone_id" {
  description = "Cloudflare zone ID for madavigo.com"
  value       = module.cloudflare_zone.zone_id
}

output "vault_auth_backend_path" {
  description = "Mount path of the Vault Kubernetes auth backend"
  value       = module.vault_auth.auth_backend_path
}
