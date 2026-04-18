variable "name" {
  description = "Short name for the service — used as HAProxy backend/server name (e.g. argocd)"
  type        = string
}

variable "hostname" {
  description = "Fully-qualified hostname clients use (e.g. argocd.madavigo.com)"
  type        = string
}

variable "target_ip" {
  description = "IP address of the upstream server"
  type        = string
}

variable "target_port" {
  description = "TCP port of the upstream server"
  type        = number
}

variable "type" {
  description = <<-EOT
    Routing class for this service. Controls which HAProxy map file gets the
    entry and how the backend server is configured.

    DEFAULT IS "local" — a service must explicitly opt in to public exposure.

      local           — LOCAL_SUBDOMAINS map, plain HTTP. Only reachable from
                        10.10.67.0/24. SAFE DEFAULT.

      local-ssl       — LOCAL_SUBDOMAINS map, SSL (verify none). LAN only.

      local-nooffload — LOCAL_NOOFFLOAD map, SSL with SNI passthrough (no TLS
                        termination at HAProxy). Use for K8s services that
                        manage their own certs and are LAN-only (e.g. music).

      cluster-public  — PUBLIC_SUBDOMAINS map, SNI passthrough to MetalLB
                        (10.10.70.0:443). Use for K8s ingresses you want public.
                        REQUIRES EXPLICIT DECLARATION.

      public          — PUBLIC_SUBDOMAINS map, plain HTTP to target.
                        REQUIRES EXPLICIT DECLARATION.

      public-ssl      — PUBLIC_SUBDOMAINS map, SSL (verify none) to target.
                        REQUIRES EXPLICIT DECLARATION.
  EOT
  type    = string
  default = "local" # safe default — must opt IN to public exposure

  validation {
    condition     = contains(["local", "local-ssl", "local-nooffload", "cluster-public", "public", "public-ssl"], var.type)
    error_message = "type must be one of: local, local-ssl, local-nooffload, cluster-public, public, public-ssl"
  }
}

# Map file UUIDs — retrieved from OPNsense API, populated in terraform.tfvars.
# Retrieve with:
#   curl -sk -u "$KEY:$SECRET" \
#     https://10.10.67.1:8443/api/haproxy/settings/searchMapfiles \
#     | jq '.rows[] | {name, uuid}'
variable "public_map_uuid" {
  description = "UUID of PUBLIC_SUBDOMAINS_Mapfile (c4b0441d-...)"
  type        = string
}

variable "local_map_uuid" {
  description = "UUID of LOCAL_SUBDOMAINS_Mapfile (05293d86-...)"
  type        = string
}

variable "local_nooffload_map_uuid" {
  description = "UUID of LOCAL_NOOFFLOAD_SUBDOMAINS_Mapfile (80b06e51-...)"
  type        = string
}
