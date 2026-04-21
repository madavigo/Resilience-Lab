variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Edit permissions for madavigo.com"
  type        = string
  sensitive   = true
}

variable "vault_address" {
  description = "Vault server URL"
  type        = string
  default     = "https://vault.madavigo.com"
}

variable "vault_token" {
  description = "Vault token with permissions to manage auth backends, mounts, and policies"
  type        = string
  sensitive   = true
}

variable "kubernetes_host" {
  description = "URL of the Kubernetes API server (for Vault Kubernetes auth config)"
  type        = string
  default     = "https://10.10.67.48:6443"
}

variable "kubernetes_ca_cert" {
  description = "PEM-encoded CA certificate for the Kubernetes cluster"
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# OPNsense
# ---------------------------------------------------------------------------
variable "opnsense_url" {
  description = "Base URL of the OPNsense firewall API (port 8443 — admin UI is not on 443)"
  type        = string
  default     = "https://badhombre.madavigo.com:8443"
}

variable "opnsense_api_key" {
  description = "OPNsense API key"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "OPNsense API secret"
  type        = string
  sensitive   = true
}

# These UUIDs identify the existing map files in OPNsense HAProxy.
# Retrieve them once with:
#   curl -sk -u "$KEY:$SECRET" \
#     https://badhombre.madavigo.com/api/haproxy/mapfile/searchMapfile \
#     | jq '.rows[] | {name, uuid}'
variable "haproxy_public_map_uuid" {
  description = "UUID of PUBLIC_SUBDOMAINS_Mapfile"
  type        = string
  default     = "c4b0441d-c005-42d6-80c8-4fadc607a5de"
}

variable "haproxy_local_map_uuid" {
  description = "UUID of LOCAL_SUBDOMAINS_Mapfile"
  type        = string
  default     = "05293d86-653f-4137-a580-cf2d6453a9e5"
}

variable "haproxy_local_nooffload_map_uuid" {
  description = "UUID of LOCAL_NOOFFLOAD_SUBDOMAINS_Mapfile"
  type        = string
  default     = "80b06e51-4d37-4418-824a-4f06e02fe5ae"
}

# ---------------------------------------------------------------------------
# Vultr
# ---------------------------------------------------------------------------
variable "vultr_api_key" {
  description = "Vultr API key — pass via TF_VAR_vultr_api_key, never commit"
  type        = string
  sensitive   = true
}

variable "vultr_ssh_public_key" {
  description = "SSH public key to inject into Vultr instances at provision time"
  type        = string
}

# ---------------------------------------------------------------------------
# General-purpose front-proxy VPS (HAProxy + WireGuard)
# ---------------------------------------------------------------------------
variable "proxy_wg_private_key" {
  description = <<-EOT
    WireGuard private key for the proxy node.
    Generate: wg genkey | tee privkey | wg pubkey > pubkey
    Then add the public key as a peer in OPNsense WireGuard (PhoneHome server).
    Pass via TF_VAR_proxy_wg_private_key — never commit.
  EOT
  type      = string
  sensitive = true
  default   = ""
}
