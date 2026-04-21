provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

provider "opnsense" {
  uri        = var.opnsense_url
  api_key    = var.opnsense_api_key
  api_secret = var.opnsense_api_secret
  # OPNsense uses a self-signed cert by default
  allow_insecure = true
}

provider "vultr" {
  api_key     = var.vultr_api_key
  rate_limit  = 100
  retry_limit = 3
}

# ---------------------------------------------------------------------------
# Vultr — SSH key (uploaded once, referenced by all Vultr instances)
# ---------------------------------------------------------------------------
resource "vultr_ssh_key" "lab" {
  name    = "resilience-lab"
  ssh_key = var.vultr_ssh_public_key
}

# ---------------------------------------------------------------------------
# Vultr — General-purpose front-proxy VPS
#
# HAProxy on :443 does TCP/SNI passthrough to internal cluster services.
# WireGuard tunnels all backend traffic to OPNsense (no WAN IP in DNS).
#
# Routing:
#   teleport.madavigo.com → 10.10.70.1:443  (Teleport MetalLB)
#   *.madavigo.com         → 10.10.70.0:443  (ingress-nginx MetalLB)
#
# WireGuard peer: resilience-lab-proxy (UUID: 185a41fe-2f3b-46d9-ac7b-955b550537a7)
# Tunnel address: 10.10.13.3/32 (PhoneHome server, OPNsense WAN 136.60.100.55:61612)
#
# BEFORE terraform apply (first provision only):
#   1. Generate a WireGuard keypair:
#        wg genkey | tee privkey | wg pubkey > pubkey
#   2. Add the public key as a peer in OPNsense WireGuard (PhoneHome server)
#      and assign tunnel IP 10.10.13.3/32
#   3. export TF_VAR_proxy_wg_private_key="$(cat privkey)"
#   4. terraform apply
#
# The running instance at 216.128.142.127 (provisioned 2026-04-20) can be
# imported:  terraform import module.proxy.vultr_instance.this <instance-id>
# ---------------------------------------------------------------------------
module "proxy" {
  source = "../../modules/vultr-vps"

  label    = "proxy"
  hostname = "proxy.madavigo.com"
  region   = "ewr"         # New Jersey — east coast
  plan     = "vc2-1c-2gb"  # 1 vCPU / 2 GB RAM / 55 GB NVMe (~$12/mo)
  os_id    = 2284           # Ubuntu 24.04 x64

  ssh_key_ids = [vultr_ssh_key.lab.id]

  user_data = templatefile("../../modules/vultr-vps/cloud-init/proxy.yaml.tpl", {
    wg_private_key  = var.proxy_wg_private_key
    wg_address      = "10.10.13.3/24"
    opnsense_wan_ip = "136.60.100.55"
  })

  firewall_rules = [
    { protocol = "tcp", port = "22",  source_cidr = "0.0.0.0/0" }, # SSH
    { protocol = "tcp", port = "443", source_cidr = "0.0.0.0/0" }, # HAProxy TLS passthrough
    { protocol = "tcp", port = "80",  source_cidr = "0.0.0.0/0" }, # HTTP
  ]

  tags = ["lab", "proxy", "haproxy"]
}

# ---------------------------------------------------------------------------
# DNS — manage madavigo.com records in Cloudflare
# ---------------------------------------------------------------------------
module "cloudflare_zone" {
  source = "../../modules/cloudflare-zone"

  zone = "madavigo.com"

  # Only publicly-routable services belong in Cloudflare.
  # LAN-only services have no Cloudflare record — internal resolution is
  # handled by OPNsense Unbound (see module "opnsense_dns" below).
  records = [
    # Front-proxy (HAProxy + WireGuard) — all public TLS goes here
    # SNI passthrough routes each hostname to the correct internal backend
    { name = "proxy",    type = "A", value = module.proxy.public_ipv4, proxied = false, comment = "General-purpose front-proxy (HAProxy + WireGuard)" },
    { name = "teleport", type = "A", value = module.proxy.public_ipv4, proxied = false, comment = "Teleport — via proxy SNI passthrough, WAN IP never in DNS" },

    # Public services via proxy SNI passthrough (not proxied by Cloudflare — HAProxy handles TLS)
    { name = "music", type = "A", value = module.proxy.public_ipv4, proxied = false, comment = "Navidrome — via proxy → ingress-nginx" },
    { name = "s",     type = "A", value = module.proxy.public_ipv4, proxied = false, comment = "Emby — via proxy → ingress-nginx" },
  ]
}

# ---------------------------------------------------------------------------
# Vault — Kubernetes auth method + ESO role
# ---------------------------------------------------------------------------
module "vault_auth" {
  source = "../../modules/vault-auth"

  kubernetes_host           = var.kubernetes_host
  kubernetes_ca_cert        = var.kubernetes_ca_cert
  service_account_name      = "external-secrets"
  service_account_namespace = "external-secrets"
  bound_namespaces          = []
  vault_role_name           = "eso-role"
  vault_policies            = ["eso-read"]

  # Tokens live long enough for ESO's background refresh cycle
  token_ttl     = 3600
  token_max_ttl = 86400
}

# ---------------------------------------------------------------------------
# OPNsense HAProxy — service routing
#
# Each module call creates a HAProxy server + backend + map file entry.
#
# EXPOSURE IS CONTROLLED BY "type". Default is "local" — must explicitly
# set type = "cluster-public" | "public" | "public-ssl" to expose publicly.
#
# Map files (UUIDs from OPNsense API):
#   PUBLIC_SUBDOMAINS        c4b0441d  — internet-accessible
#   LOCAL_SUBDOMAINS         05293d86  — 10.10.67.0/24 only
#   LOCAL_NOOFFLOAD          80b06e51  — 10.10.67.0/24, no TLS offload
#
# Types:
#   local           → LOCAL map, plain HTTP           (LAN only, safe default)
#   local-ssl       → LOCAL map, SSL verify none      (LAN only)
#   local-nooffload → LOCAL_NOOFFLOAD map, SNI passthrough (LAN only, K8s certs)
#   cluster-public  → PUBLIC map, SNI passthrough to MetalLB  ← INTENTIONAL ONLY
#   public          → PUBLIC map, plain HTTP to target         ← INTENTIONAL ONLY
#   public-ssl      → PUBLIC map, SSL verify none to target    ← INTENTIONAL ONLY
# ---------------------------------------------------------------------------

locals {
  # Convenience: pass all three map UUIDs to every module call
  map_uuids = {
    public_map_uuid          = var.haproxy_public_map_uuid
    local_map_uuid           = var.haproxy_local_map_uuid
    local_nooffload_map_uuid = var.haproxy_local_nooffload_map_uuid
  }
}

# ===========================================================================
# LEGACY PUBLIC — music, emby/s
#
# These predate the Vultr front-proxy. With proxy.madavigo.com now fronting
# every public A record in Cloudflare, public traffic for music/s is:
#     internet → Cloudflare → Vultr VPS HAProxy → 10.10.70.0 (ingress-nginx)
# — it never reaches OPNsense HAProxy. These blocks still manage the OPNsense
# backends for split-horizon LAN access (and as a fallback if the VPS is down),
# but they're optional. Safe to remove once Unbound split-DNS is confirmed
# covering every LAN client.
#
# These already exist in OPNsense — import before first apply:
#   terraform import module.haproxy_<name>.opnsense_haproxy_server.this <server-uuid>
#   terraform import module.haproxy_<name>.opnsense_haproxy_backend.this <backend-uuid>
#   terraform import module.haproxy_<name>.opnsense_haproxy_mapfile_entry.this <entry-uuid>
# ===========================================================================

module "haproxy_music" {
  source = "../../modules/opnsense-service"
  name        = "music"
  hostname    = "music.madavigo.com"
  type        = "cluster-public" # PUBLIC_SUBDOMAINS map, SNI passthrough to MetalLB
  target_ip   = "10.10.70.0"
  target_port = 443
  public_map_uuid          = local.map_uuids.public_map_uuid
  local_map_uuid           = local.map_uuids.local_map_uuid
  local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
}

module "haproxy_emby" {
  source = "../../modules/opnsense-service"
  name        = "emby"
  hostname    = "s.madavigo.com"
  type        = "public" # Public — direct HTTP to TrueNAS
  target_ip   = "10.10.67.170"
  target_port = 9096
  public_map_uuid          = local.map_uuids.public_map_uuid
  local_map_uuid           = local.map_uuids.local_map_uuid
  local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
}

# ===========================================================================
# LOCAL-ONLY — existing services (LAN access only)
# ===========================================================================

module "haproxy_gitea" {
  source = "../../modules/opnsense-service"
  name        = "gitea"
  hostname    = "git.madavigo.com"
  type        = "local"
  target_ip   = "10.10.67.170"
  target_port = 30008
  public_map_uuid          = local.map_uuids.public_map_uuid
  local_map_uuid           = local.map_uuids.local_map_uuid
  local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
}

module "haproxy_unifi" {
  source = "../../modules/opnsense-service"
  name        = "unifi"
  hostname    = "unifi.madavigo.com"
  type        = "local-ssl"
  target_ip   = "10.10.67.170"
  target_port = 30072
  public_map_uuid          = local.map_uuids.public_map_uuid
  local_map_uuid           = local.map_uuids.local_map_uuid
  local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
}

module "haproxy_ha" {
  source = "../../modules/opnsense-service"
  name        = "ha"
  hostname    = "ha.madavigo.com"
  type        = "local"
  target_ip   = "10.10.67.170"
  target_port = 20810
  public_map_uuid          = local.map_uuids.public_map_uuid
  local_map_uuid           = local.map_uuids.local_map_uuid
  local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
}

# ===========================================================================
# FUTURE CLUSTER SERVICES — no active HAProxy backends yet
#
# These services are managed by ArgoCD/ingress-nginx and resolve via Unbound
# to MetalLB (10.10.70.0). HAProxy backends for them currently exist in
# OPNsense as disabled stale config from a previous setup.
#
# Workflow to add a service to HAProxy via Terraform:
#   1. Uncomment the module block below
#   2. Run: terraform apply -target=module.haproxy_<name>
#   3. To make it public: also add a Cloudflare record above and set type="cluster-public"
#
# module "haproxy_argocd" {
#   source = "../../modules/opnsense-service"
#   name        = "argocd"
#   hostname    = "argocd.madavigo.com"
#   type        = "local"   # → "cluster-public" to expose publicly
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_vault" {
#   source = "../../modules/opnsense-service"
#   name        = "vault"
#   hostname    = "vault.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_grafana" {
#   source = "../../modules/opnsense-service"
#   name        = "grafana"
#   hostname    = "grafana.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_prometheus" {
#   source = "../../modules/opnsense-service"
#   name        = "prometheus"
#   hostname    = "prometheus.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_alertmanager" {
#   source = "../../modules/opnsense-service"
#   name        = "alertmanager"
#   hostname    = "alertmanager.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_auth" {
#   source = "../../modules/opnsense-service"
#   name        = "auth"
#   hostname    = "auth.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_home" {
#   source = "../../modules/opnsense-service"
#   name        = "home"
#   hostname    = "home.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_workflows" {
#   source = "../../modules/opnsense-service"
#   name        = "workflows"
#   hostname    = "workflows.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_sonarr" {
#   source = "../../modules/opnsense-service"
#   name        = "sonarr"
#   hostname    = "sonarr.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_radarr" {
#   source = "../../modules/opnsense-service"
#   name        = "radarr"
#   hostname    = "radarr.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_prowlarr" {
#   source = "../../modules/opnsense-service"
#   name        = "prowlarr"
#   hostname    = "prowlarr.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_nzbget" {
#   source = "../../modules/opnsense-service"
#   name        = "nzbget"
#   hostname    = "nzbget.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
#
# module "haproxy_minio" {
#   source = "../../modules/opnsense-service"
#   name        = "minio"
#   hostname    = "minio.madavigo.com"
#   type        = "local"
#   target_ip   = "10.10.70.0"
#   target_port = 443
#   public_map_uuid          = local.map_uuids.public_map_uuid
#   local_map_uuid           = local.map_uuids.local_map_uuid
#   local_nooffload_map_uuid = local.map_uuids.local_nooffload_map_uuid
# }
# ===========================================================================

# ---------------------------------------------------------------------------
# OPNsense Unbound — internal DNS for LAN-only services
#
# These entries are served by OPNsense Unbound to clients on 10.10.67.0/24.
# None of these hostnames appear in Cloudflare — from the internet they don't
# resolve at all. HAProxy's LOCAL_condition ACL (src 10.10.67.0/24) then
# routes the traffic to the appropriate backend.
#
# To make a service public:
#   1. Remove it from this list (or leave it — having both is fine for split-horizon)
#   2. Add a Cloudflare record in module "cloudflare_zone" above
#   3. Change the haproxy_<name> module type to "cluster-public"
# ---------------------------------------------------------------------------
module "opnsense_dns" {
  source = "../../modules/opnsense-dns"

  hosts = [
    # Cluster services — resolve to MetalLB ingress (10.10.70.0)
    # Unbound returns this IP to LAN clients; HAProxy receives the request and
    # routes it via the LOCAL_SUBDOMAINS map to the correct backend.
    { hostname = "alertmanager", domain = "madavigo.com", ip = "10.10.70.0", description = "Alertmanager" },
    { hostname = "argocd",       domain = "madavigo.com", ip = "10.10.70.0", description = "ArgoCD" },
    { hostname = "auth",         domain = "madavigo.com", ip = "10.10.70.0", description = "Authentik" },
    { hostname = "ceph",         domain = "madavigo.com", ip = "10.10.70.0", description = "Rook Ceph" },
    { hostname = "grafana",      domain = "madavigo.com", ip = "10.10.70.0", description = "Grafana" },
    { hostname = "home",         domain = "madavigo.com", ip = "10.10.70.0", description = "Homepage" },
    { hostname = "minio",        domain = "madavigo.com", ip = "10.10.70.0", description = "MinIO" },
    { hostname = "nzbget",       domain = "madavigo.com", ip = "10.10.70.0", description = "NZBGet" },
    { hostname = "prometheus",   domain = "madavigo.com", ip = "10.10.70.0", description = "Prometheus" },
    { hostname = "prowlarr",     domain = "madavigo.com", ip = "10.10.70.0", description = "Prowlarr" },
    { hostname = "radarr",       domain = "madavigo.com", ip = "10.10.70.0", description = "Radarr" },
    { hostname = "sonarr",       domain = "madavigo.com", ip = "10.10.70.0", description = "Sonarr" },
    { hostname = "vault",        domain = "madavigo.com", ip = "10.10.70.0", description = "HashiCorp Vault" },
    { hostname = "workflows",    domain = "madavigo.com", ip = "10.10.70.0", description = "Argo Workflows" },

    # music: also resolves to MetalLB from LAN — avoids Cloudflare hairpin
    { hostname = "music", domain = "madavigo.com", ip = "10.10.70.0", description = "Navidrome" },

    # Non-cluster LAN-only services — resolve to OPNsense LAN IP (HAProxy local ACL routes them)
    { hostname = "git",   domain = "madavigo.com", ip = "10.10.67.1", description = "Gitea" },
    { hostname = "ha",    domain = "madavigo.com", ip = "10.10.67.1", description = "Home Assistant" },
    { hostname = "unifi", domain = "madavigo.com", ip = "10.10.67.1", description = "Unifi" },
  ]
}

# ---------------------------------------------------------------------------
# Vault — KV v2 secret engine + policies
# ---------------------------------------------------------------------------
module "vault_secret_engine" {
  source = "../../modules/vault-secret-engine"

  mount_path  = "secret"
  description = "Resilience-Lab KV v2 secret store"

  policies = {
    "eso-read" = <<-EOT
      # Allow External Secrets Operator to read all lab secrets
      path "secret/data/resilience-lab/*" {
        capabilities = ["read"]
      }
      path "secret/metadata/resilience-lab/*" {
        capabilities = ["read", "list"]
      }
    EOT
  }
}
