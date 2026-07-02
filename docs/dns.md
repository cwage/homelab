# DNS

## Internal: `lan.quietlife.net`

Internal DNS uses a split setup between two hosts:

```
LAN clients → fw1 (Unbound, recursive) → dns1 (NSD, authoritative)
                                        → root/TLD/authoritative servers (everything else)
```

**fw1** (10.10.15.1) runs **Unbound** as the recursive resolver for all LAN and VPN clients. DHCP hands out fw1 as the DNS server. Unbound stubs queries for `lan.quietlife.net` and `15.10.10.in-addr.arpa` to dns1; everything else is resolved by full recursion from the root servers with DNSSEC validation — no upstream forwarder dependency (issue #263 documents the Cloudflare outage that motivated this). fw1's own `resolv.conf` keeps `1.1.1.1` in second position as an emergency fallback for when local Unbound itself is down.

**dns1** (10.10.15.15) runs **NSD** as the authoritative server for the `lan.quietlife.net` forward zone (NixOS). It serves A records for infrastructure hosts and CNAME records for container services pointing to `containers.lan.quietlife.net`.

### Zone records

Managed inline in `hosts/dns1/configuration.nix` (NixOS NSD config). Current records include:

- A records for infrastructure: fw1, dns1, pve1, containers, portanas, bao, etc.
- CNAMEs for services: jellyfin, radarr, sonarr, sabnzbd, paperless, traefik, staticomment — all pointing to `containers`
- Convenience aliases: `firewall` → fw1, `nas` → portanas, `proxmox` → pve1

### Adding or changing DNS records

1. Edit zone data in `hosts/dns1/configuration.nix` (forward and/or reverse zone)
2. Bump the serial number in each zone you modified (format: `YYYYMMDDNN`) — forward and reverse zones have separate serials
3. Deploy: `make nix-deploy-host HOST=dns1 TARGET=10.10.15.15`

Unbound/DHCP config on fw1 is still Ansible-managed: `make ansible-firewall`

## External: Cloudflare

Public DNS zones (including `quietlife.net`) are hosted on **Cloudflare**. External access to internal services (Jellyfin) is provided via a **Cloudflare Tunnel** rather than exposing ports — see [docs/services.md](services.md).

### OpenTofu-managed DNS records

Individual Cloudflare DNS records can be managed via OpenTofu (`tofu/cloudflare.tf`). The Cloudflare provider authenticates using an API token fetched from OpenBao at plan/apply time — no credentials in `.env` beyond the existing `BAO_ADDR`/`BAO_TOKEN`.

**How it works**: Each `cloudflare_record` resource in Tofu manages a single DNS record. Records not defined in Tofu are left untouched — you can continue editing those in the Cloudflare dashboard. However, once a record is managed by Tofu, dashboard edits to that record will show as drift on the next `tofu plan`.

**Adding a DNS record**:

1. Ensure the zone has a `data "cloudflare_zone"` lookup in `tofu/cloudflare.tf`
2. Add a `cloudflare_record` resource:
   ```hcl
   resource "cloudflare_record" "example" {
     zone_id = data.cloudflare_zone.quietlife.id
     name    = "example"
     value   = "1.2.3.4"
     type    = "A"
     proxied = false
   }
   ```
3. Run `make tofu-plan` to preview, `make tofu-apply` to create

**Importing existing records**: If you want Tofu to manage a record that already exists in Cloudflare, use `cf-terraforming` to generate the HCL and import commands, or manually `tofu import` the record. Only import records you intend to manage going forward.

### Cloudflare Tunnel

The `cloudflared` container runs on the containers host and provides external access to selected services without exposing ports. The tunnel token is stored in OpenBao at `kv/infra/cloudflare/tunnel`. See [docs/services.md](services.md) for details.

Tunnel ingress routes (which hostnames map to which internal services) can be managed via OpenTofu using `cloudflare_tunnel_config` resources; the Cloudflare provider and credentials are in place, but no tunnel resources are defined in Tofu yet. Currently, all routes are configured in the Cloudflare Zero Trust dashboard.

### DNS-01 ACME challenges

The `lego/` tooling uses a separate Cloudflare API token (stored at `kv/infra/cloudflare`) to create TXT records for Let's Encrypt wildcard certificate validation (`*.lan.quietlife.net`). See [docs/tls-certificates.md](tls-certificates.md).

### Cloudflare API credentials

Three tokens are stored in OpenBao for different purposes:

| OpenBao path | Fields | Used by |
|-------------|--------|---------|
| `kv/infra/cloudflare` | `api_token`, `zone_id` | lego ACME client (cert renewal) |
| `kv/infra/cloudflare/tunnel` | `token` | cloudflared container (tunnel runtime) |
| `kv/infra/cloudflare/tofu` | `api_token`, `account_id` | OpenTofu Cloudflare provider (DNS + tunnel management) |

The Tofu token has broader permissions (all zones, tunnel management) while the lego token is scoped to `quietlife.net` DNS only.
