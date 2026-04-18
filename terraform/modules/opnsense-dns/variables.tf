variable "hosts" {
  description = <<-EOT
    List of Unbound host override entries. Each entry creates an internal DNS
    record served by OPNsense Unbound for clients on the LAN.

    Use this for services that should only resolve from inside the network —
    the names will NOT appear in Cloudflare/public DNS, so they're unreachable
    from the internet even if someone knows the hostname.

    Fields:
      hostname    — short name, e.g. "argocd" (not the FQDN)
      domain      — domain suffix, e.g. "madavigo.com"
      ip          — IP the name should resolve to internally
      description — optional human-readable label shown in OPNsense UI
  EOT
  type = list(object({
    hostname    = string
    domain      = string
    ip          = string
    description = optional(string, "")
  }))
}
