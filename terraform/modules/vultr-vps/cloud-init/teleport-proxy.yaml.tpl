#cloud-config

# Teleport Proxy Tier — cloud-init bootstrap
# Runs once on first boot. Installs Teleport, writes config, starts service.
# SSH password auth disabled. Port 22 not open in firewall — access via Teleport only.
#
# Template variables (rendered by Terraform templatefile()):
#   teleport_version  — major version number (e.g. "16")
#   join_token        — one-time join token generated from cluster (tctl tokens add)
#   proxy_public_addr — public FQDN of this proxy (e.g. teleport.madavigo.com)
#   acme_email        — email address for Let's Encrypt ACME registration

package_update: true
package_upgrade: true

packages:
  - curl
  - gnupg
  - ca-certificates

write_files:
  - path: /etc/teleport.yaml
    permissions: "0600"
    content: |
      version: v3
      teleport:
        nodename: teleport-proxy
        data_dir: /var/lib/teleport
        log:
          output: stderr
          severity: INFO
        join_params:
          token_name: ${join_token}
          method: token
        proxy_server: ${proxy_public_addr}:443

      proxy_service:
        enabled: true
        public_addr: ${proxy_public_addr}:443
        ssh_public_addr: ${proxy_public_addr}:3022
        tunnel_public_addr: ${proxy_public_addr}:3024
        web_listen_addr: 0.0.0.0:443
        tunnel_listen_addr: 0.0.0.0:3024
        # Let Teleport manage its own TLS via ACME (Let's Encrypt)
        acme:
          enabled: true
          email: ${acme_email}

      auth_service:
        enabled: false

      ssh_service:
        enabled: false

runcmd:
  # Install Teleport (install.sh accepts major version, pins to latest patch)
  - curl https://cdn.teleport.dev/install.sh | bash -s ${teleport_version}
  # Enable and start — config already written by write_files above
  - systemctl enable teleport
  - systemctl start teleport

# Harden SSH — no password auth, no root login
# Port 22 is not open in the Vultr firewall anyway
ssh_pwauth: false
disable_root: true
