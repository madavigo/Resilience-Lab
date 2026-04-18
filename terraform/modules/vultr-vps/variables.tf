variable "label" {
  description = "Display name for the instance in the Vultr console"
  type        = string
}

variable "hostname" {
  description = "FQDN of the instance (e.g. teleport.madavigo.com)"
  type        = string
}

variable "region" {
  description = "Vultr region ID"
  type        = string
  default     = "dfw" # Dallas — domestic US, good latency from central
}

variable "plan" {
  description = "Vultr plan ID (vc2-1c-1gb = 1 vCPU / 1 GB RAM / 25 GB NVMe, ~$6/mo)"
  type        = string
  default     = "vc2-1c-1gb"
}

variable "os_id" {
  description = "Vultr OS image ID. Default: Debian 12 x64 (2076)"
  type        = number
  default     = 2076
}

variable "ssh_key_ids" {
  description = "List of Vultr SSH key UUIDs to inject at provision time"
  type        = list(string)
  default     = []
}

variable "user_data" {
  description = "cloud-init cloud-config payload (rendered template string). Runs once on first boot."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  description = "List of tags to apply to the instance in the Vultr console"
  type        = list(string)
  default     = ["lab"]
}

variable "acme_email" {
  description = "Email address for Let's Encrypt ACME registration (used in Teleport cloud-init)"
  type        = string
}

variable "firewall_rules" {
  description = <<-EOT
    Inbound firewall rules. Each object has:
      protocol    — tcp | udp | icmp
      port        — single port ("443") or range ("8000:8999")
      source_cidr — source IPv4 CIDR ("0.0.0.0/0" for any)
  EOT
  type = list(object({
    protocol    = string
    port        = string
    source_cidr = string
  }))
  # Default: nothing open — caller must explicitly pass rules
  default = []
}
