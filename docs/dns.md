# DNS

## Internal: `lan.quietlife.net`

Internal DNS uses a split setup between two hosts:

```
LAN clients → fw1 (Unbound, recursive) → dns1 (NSD, authoritative)
                                        → upstream (everything else)
```

**fw1** (10.10.15.1) runs **Unbound** as the recursive resolver for all LAN and VPN clients. DHCP hands out fw1 as the DNS server. Unbound stubs queries for `lan.quietlife.net` and `15.10.10.in-addr.arpa` to dns1; all other queries go upstream.

**dns1** (10.10.15.15) runs **NSD** as the authoritative server for the `lan.quietlife.net` forward zone (NixOS). It serves A records for infrastructure hosts and CNAME records for container services pointing to `containers.lan.quietlife.net`.

### Zone records

Managed inline in `hosts/dns1/configuration.nix` (NixOS NSD config). Current records include:

- A records for infrastructure: fw1, dns1, pve1, containers, portanas, bao, etc.
- CNAMEs for services: jellyfin, radarr, sonarr, sabnzbd, paperless, owncast, traefik — all pointing to `containers`
- Convenience aliases: `firewall` → fw1, `nas` → portanas, `proxmox` → pve1

### Adding or changing DNS records

1. Edit zone data in `hosts/dns1/configuration.nix` (forward and/or reverse zone)
2. Bump the serial number in each zone you modified (format: `YYYYMMDDNN`) — forward and reverse zones have separate serials
3. Deploy: `make nix-deploy-host HOST=dns1 TARGET=10.10.15.15`

Unbound/DHCP config on fw1 is still Ansible-managed: `make ansible-firewall`

## External: `quietlife.net`

The public `quietlife.net` zone is hosted on **Cloudflare**. This serves two purposes:

1. **Public DNS** for any external-facing records
2. **DNS-01 ACME challenges** for Let's Encrypt wildcard certificate (`*.lan.quietlife.net`). The `lego/` tooling uses the Cloudflare API to create TXT records for validation. See [docs/tls-certificates.md](tls-certificates.md).

External access to internal services (Jellyfin, Owncast) is provided via a **Cloudflare Tunnel** rather than exposing ports — see [docs/services.md](services.md).

### Cloudflare API credentials

Stored in OpenBao at `kv/infra/cloudflare`. The API token requires `Zone:DNS:Edit` and `Zone:Zone:Read` permissions. Used by the lego ACME client for cert renewal.
