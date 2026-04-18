variable "zone" {
  description = "The Cloudflare zone name (e.g. madavigo.com)"
  type        = string
}

variable "records" {
  description = "List of DNS records to manage"
  type = list(object({
    name    = string
    type    = string
    value   = string
    ttl     = optional(number, 1)     # 1 = automatic (Cloudflare proxied)
    proxied = optional(bool, false)
    comment = optional(string, "")
  }))
  default = []
}
