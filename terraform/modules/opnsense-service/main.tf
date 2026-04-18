terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.10"
    }
  }
}

locals {
  is_public   = contains(["cluster-public", "public", "public-ssl"], var.type)
  is_nooffload = var.type == "local-nooffload"
  use_ssl     = contains(["cluster-public", "public-ssl", "local-ssl", "local-nooffload"], var.type)
  use_sni     = contains(["cluster-public", "local-nooffload"], var.type)

  target_map_uuid = local.is_public ? var.public_map_uuid : (
    local.is_nooffload ? var.local_nooffload_map_uuid : var.local_map_uuid
  )
}

# ---------------------------------------------------------------------------
# HAProxy server (backend pool member)
# ---------------------------------------------------------------------------
resource "opnsense_haproxy_server" "this" {
  name    = var.name
  address = var.target_ip
  port    = tostring(var.target_port)

  ssl          = local.use_ssl
  ssl_verify   = false # self-signed certs throughout the lab
  ssl_sni      = local.use_sni ? var.hostname : null

  checktype = "none"
}

# ---------------------------------------------------------------------------
# HAProxy backend (pool)
# ---------------------------------------------------------------------------
resource "opnsense_haproxy_backend" "this" {
  name    = var.name
  mode    = "http"
  balance = "source"

  servers = [opnsense_haproxy_server.this.id]

  http_reuse        = "safe"
  forwarded_for     = true
  stickiness_type   = "sourceipv4"
  stickiness_expire = "30m"
  stickiness_size   = "50k"

  depends_on = [opnsense_haproxy_server.this]
}

# ---------------------------------------------------------------------------
# Map entry — hostname → backend name in the correct map file
# ---------------------------------------------------------------------------
resource "opnsense_haproxy_mapfile_entry" "this" {
  mapfile_uuid = local.target_map_uuid
  key          = var.hostname
  value        = var.name

  depends_on = [opnsense_haproxy_backend.this]
}
