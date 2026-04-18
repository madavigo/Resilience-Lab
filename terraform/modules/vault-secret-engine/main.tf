terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

# KV v2 secret engine mount.
# If the mount already exists (manually enabled), import it:
#   terraform import vault_mount.kv <mount_path>
resource "vault_mount" "kv" {
  path        = var.mount_path
  type        = "kv"
  description = var.description

  options = {
    version = "2"
  }
}

# One vault_policy resource per entry in var.policies.
# Key   = policy name (e.g. "eso-read")
# Value = HCL policy document string
resource "vault_policy" "policies" {
  for_each = var.policies

  name   = each.key
  policy = each.value

  depends_on = [vault_mount.kv]
}
