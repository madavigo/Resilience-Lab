variable "kubernetes_host" {
  description = "URL of the Kubernetes API server"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "PEM-encoded CA certificate for the Kubernetes cluster"
  type        = string
  sensitive   = true
}

variable "service_account_name" {
  description = "Kubernetes service account name allowed to authenticate"
  type        = string
}

variable "service_account_namespace" {
  description = "Kubernetes namespace the service account lives in"
  type        = string
}

variable "bound_namespaces" {
  description = "Additional namespaces permitted to use this role"
  type        = list(string)
  default     = []
}

variable "vault_role_name" {
  description = "Name of the Vault Kubernetes auth role to create"
  type        = string
}

variable "vault_policies" {
  description = "Vault policies to attach to the role"
  type        = list(string)
}

variable "token_ttl" {
  description = "Default TTL (seconds) for tokens issued by this role"
  type        = number
  default     = 3600
}

variable "token_max_ttl" {
  description = "Maximum TTL (seconds) for tokens issued by this role"
  type        = number
  default     = 86400
}
