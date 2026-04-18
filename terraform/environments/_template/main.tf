provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

# ---------------------------------------------------------------------------
# Add module calls here. Example:
#
# module "cloudflare_zone" {
#   source  = "../../modules/cloudflare-zone"
#   zone    = "example.com"
#   records = []
# }
# ---------------------------------------------------------------------------
