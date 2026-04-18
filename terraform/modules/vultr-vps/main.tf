terraform {
  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.27"
    }
  }
}

# ---------------------------------------------------------------------------
# Firewall group — scoped to this instance
# ---------------------------------------------------------------------------
resource "vultr_firewall_group" "this" {
  description = var.label
}

# One firewall rule per entry in var.firewall_rules.
# Key on protocol+port to allow the same port over different protocols.
resource "vultr_firewall_rule" "rules" {
  for_each = {
    for r in var.firewall_rules : "${r.protocol}-${r.port}" => r
  }

  firewall_group_id = vultr_firewall_group.this.id
  protocol          = each.value.protocol
  ip_type           = "v4"
  subnet            = split("/", each.value.source_cidr)[0]
  subnet_size       = tonumber(split("/", each.value.source_cidr)[1])
  port              = each.value.port
}

# ---------------------------------------------------------------------------
# Compute instance
# ---------------------------------------------------------------------------
resource "vultr_instance" "this" {
  label     = var.label
  hostname  = var.hostname
  region    = var.region
  plan      = var.plan
  os_id     = var.os_id
  tags      = var.tags

  firewall_group_id = vultr_firewall_group.this.id
  ssh_key_ids       = var.ssh_key_ids
  user_data         = var.user_data

  backups     = "disabled"
  enable_ipv6 = false

  # Prevent Terraform from destroying and recreating the instance if
  # user_data changes after initial provision — cloud-init runs once only.
  lifecycle {
    ignore_changes = [user_data]
  }

  depends_on = [vultr_firewall_rule.rules]
}
