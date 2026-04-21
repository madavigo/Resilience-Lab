# Non-sensitive defaults. Sensitive values (API tokens, Vault token, CA cert)
# must be set via environment variables or a local override file:
#
#   export TF_VAR_cloudflare_api_token="..."
#   export TF_VAR_vault_token="..."
#   export TF_VAR_kubernetes_ca_cert="$(kubectl config view --raw --minify \
#     --output 'jsonpath={.clusters[0].cluster.certificate-authority-data}' | base64 -d)"
#
# Or create terraform.tfvars.local (gitignored) with the sensitive values.

vault_address   = "https://vault.madavigo.com"
kubernetes_host = "https://10.10.67.48:6443"
# OPNsense admin UI is on port 8443 (HAProxy owns :443 for public services)
opnsense_url    = "https://badhombre.madavigo.com:8443"

# Map file UUIDs (retrieved from OPNsense API 2026-04-15)
haproxy_public_map_uuid          = "c4b0441d-c005-42d6-80c8-4fadc607a5de"
haproxy_local_map_uuid           = "05293d86-653f-4137-a580-cf2d6453a9e5"
haproxy_local_nooffload_map_uuid = "80b06e51-4d37-4418-824a-4f06e02fe5ae"
