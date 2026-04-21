#cloud-config
# ---------------------------------------------------------------------------
# General-purpose front-proxy: HAProxy (SNI TCP passthrough) + WireGuard
#
# HAProxy listens on :443 and routes by SNI to internal cluster services via
# a WireGuard tunnel to OPNsense (PhoneHome server, 10.10.13.0/24).
#
# The WireGuard tunnel reaches:
#   10.10.67.0/24 — HomeLab LAN (cluster nodes, OPNsense)
#   10.10.70.0/24 — MetalLB pool (ingress-nginx: .0, Teleport: .1)
# ---------------------------------------------------------------------------

package_update: true
package_upgrade: false

packages:
  - wireguard
  - haproxy

write_files:
  - path: /etc/wireguard/wg0.conf
    permissions: "0600"
    owner: root:root
    content: |
      [Interface]
      PrivateKey = ${wg_private_key}
      Address    = ${wg_address}

      [Peer]
      # OPNsense WireGuard — PhoneHome server
      PublicKey  = TzDGG7U1bJYdjDkfp920QwkKLipen8Ay4eTSqlj0uns=
      Endpoint   = ${opnsense_wan_ip}:61612
      AllowedIPs = 10.10.13.0/24, 10.10.67.0/24, 10.10.70.0/24
      PersistentKeepalive = 25

  - path: /etc/haproxy/haproxy.cfg
    permissions: "0644"
    owner: root:root
    content: |
      global
        log /dev/log local0
        log /dev/log local1 notice
        maxconn 4096
        user haproxy
        group haproxy
        daemon

      defaults
        log     global
        mode    tcp
        option  tcplog
        option  dontlognull
        timeout connect 5s
        timeout client  30s
        timeout server  30s
        timeout client-fin 30s

      # -----------------------------------------------------------------------
      # Frontend: all TLS on port 443 — route by SNI, no TLS termination
      # -----------------------------------------------------------------------
      frontend tls_sni
        bind *:443
        mode tcp
        option tcplog
        tcp-request inspect-delay 5s
        tcp-request content accept if { req_ssl_hello_type 1 }

        # Teleport — ALPN-multiplexed: web UI, kubectl, SSH
        use_backend bk_teleport if { req.ssl_sni -i teleport.madavigo.com }

        # Default: ingress-nginx (all other *.madavigo.com services)
        default_backend bk_ingress

      # -----------------------------------------------------------------------
      # Backend: Teleport cluster (MetalLB 10.10.70.1)
      # -----------------------------------------------------------------------
      backend bk_teleport
        mode tcp
        option ssl-hello-chk
        server teleport 10.10.70.1:443 check inter 10s

      # -----------------------------------------------------------------------
      # Backend: ingress-nginx (MetalLB 10.10.70.0)
      # -----------------------------------------------------------------------
      backend bk_ingress
        mode tcp
        option ssl-hello-chk
        server ingress 10.10.70.0:443 check inter 10s

runcmd:
  # UFW: allow SSH + HTTPS + WireGuard keepalive
  - ufw allow 22/tcp
  - ufw allow 443/tcp
  - ufw allow 80/tcp
  - ufw --force enable

  # WireGuard: enable and start tunnel
  - systemctl enable wg-quick@wg0
  - systemctl start wg-quick@wg0

  # HAProxy: enable and (re)start with new config
  - systemctl enable haproxy
  - systemctl restart haproxy
