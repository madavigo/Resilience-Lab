variable "mount_path" {
  description = "Path at which to mount the KV v2 secret engine (e.g. secret)"
  type        = string
  default     = "secret"
}

variable "description" {
  description = "Human-readable description for the mount"
  type        = string
  default     = ""
}

variable "policies" {
  description = "Map of policy name -> HCL policy document to create"
  type        = map(string)
  default     = {}
}
