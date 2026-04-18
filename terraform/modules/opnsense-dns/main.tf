terraform {
  required_providers {
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.10"
    }
  }
}

# One Unbound host override per entry in var.hosts.
# Keyed on hostname so the for_each map key is stable — renaming a host
# destroys and recreates only that entry, not the whole set.
resource "opnsense_unbound_host" "hosts" {
  for_each = { for h in var.hosts : h.hostname => h }

  hostname    = each.value.hostname
  domain      = each.value.domain
  server      = each.value.ip
  description = each.value.description
  enabled     = true
}
