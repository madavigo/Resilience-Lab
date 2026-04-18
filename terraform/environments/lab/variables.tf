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
  description = "Base URL of the OPNsense firewall API"
  type        = string
  default     = "https://badhombre.madavigo.com"
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
# Teleport proxy VPS
# ---------------------------------------------------------------------------
variable "teleport_join_token" {
  description = <<-EOT
    One-time Teleport join token for the proxy to authenticate against the
    cluster auth service. Generate before terraform apply:
      kubectl --kubeconfig ~/.kube/config-resilience-lab \
        -n teleport exec deploy/teleport -- \
        tctl tokens add --type=proxy --ttl=1h
    Pass via TF_VAR_teleport_join_token — consumed on first boot, never reused.
  EOT
  type      = string
  sensitive = true
}

variable "teleport_acme_email" {
  description = "Email address for Let's Encrypt ACME registration on the Teleport proxy VPS"
  type        = string
  default     = "mgolden@een.com"
}

variable "teleport_version" {
  description = "Teleport major version to install (install.sh resolves latest patch)"
  type        = string
  default     = "16"
}

variable "teleport_proxy_hostname" {
  description = "Public FQDN for the Teleport proxy tier"
  type        = string
  default     = "teleport.madavigo.com"
}
