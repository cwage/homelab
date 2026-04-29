# Services

All self-hosted services run as Docker containers on the **containers2** host (`10.10.15.11`), a NixOS VM managed via `hosts/containers2/configuration.nix`. The compose stack lives at `hosts/containers2/stacks/docker-compose.yml` and is symlinked into `/opt/stacks/` from the nix store. Traefik handles reverse proxying and TLS termination with a wildcard certificate for `*.lan.quietlife.net`.

## Service inventory

| Service | Image | Internal URL | Purpose |
|---------|-------|-------------|---------|
| **Traefik** | `traefik:v2.11` | `https://traefik.lan.quietlife.net` | Reverse proxy, TLS termination, dashboard |
| **Jellyfin** | `linuxserver/jellyfin` | `https://jellyfin.lan.quietlife.net` | Media server (NVENC GPU transcoding) |
| **Radarr** | `linuxserver/radarr` | `https://radarr.lan.quietlife.net` | Movie automation |
| **Sonarr** | `linuxserver/sonarr` | `https://sonarr.lan.quietlife.net` | TV automation |
| **SABnzbd** | `linuxserver/sabnzbd` | `https://sabnzbd.lan.quietlife.net` | Usenet download client |
| **Paperless-ngx** | `paperless-ngx/paperless-ngx` | `https://paperless.lan.quietlife.net` | Document management |
| **Paperless Redis** | `redis` | — | Backend for Paperless-ngx |
| **staticomment** | `ghcr.io/cwage/staticomment` | `https://staticomment.lan.quietlife.net` | Comment endpoint for `quietlife.net` |
| **Cloudflared** | `cloudflare/cloudflared` | — | Cloudflare Tunnel for external access (Jellyfin) |

## External access

Jellyfin is exposed externally via a Cloudflare Tunnel (`cloudflared` container). The tunnel token is stored in OpenBao at `kv/infra/cloudflare/tunnel`. Tunnel ingress routes are configured in the Cloudflare Zero Trust dashboard.

## How it fits together

```
Internet → Cloudflare Tunnel → cloudflared container ─┐
                                                       ↓
LAN clients → fw1 (DNS) → containers2:443 → Traefik → service containers
                                              ↑
                                     wildcard TLS cert
                                   (see docs/tls-certificates.md)
```

- **DNS**: Each service has a CNAME record in the NSD zone pointing to `containers2.lan.quietlife.net`
- **TLS**: Traefik serves a wildcard cert for `*.lan.quietlife.net` (see [docs/tls-certificates.md](tls-certificates.md))
- **Storage**: Jellyfin, Radarr, Sonarr, and SABnzbd share `/mnt/nas/Media` (NFS from NAS). Paperless uses `/mnt/nas/paperless`.

## NFS mounts

containers2 mounts NAS shares under `/mnt/nas/`:

| Mount | NAS share | Used by |
|-------|-----------|---------|
| `/mnt/nas/Media` | `portanas:/volume1/Media` | Jellyfin, Radarr, Sonarr, SABnzbd |
| `/mnt/nas/paperless` | `portanas:/volume1/paperless` | Paperless-ngx |

Additional NAS shares are mounted read-only for backup access. See the `fileSystems` block in `hosts/containers2/configuration.nix` for the full list.

## Deployment

```bash
make nix-deploy-host HOST=containers2 TARGET=10.10.15.11
```

`hosts/containers2/configuration.nix` declares:
1. Docker + NVIDIA container toolkit (CDI + legacy `nvidia` runtime)
2. NFS mounts
3. `/opt/stacks/` populated via `systemd.tmpfiles` symlinks from the nix store
4. Mutable secrets (`.env`, traefik basicauth, staticomment SSH key) and TLS certs in `/opt/stacks/` — slated to migrate to openbao-agent / lego
5. B2/local/configs backup systemd timers via `modules/backups.nix`

## Adding a new service

1. Add the service to `hosts/containers2/stacks/docker-compose.yml` with Traefik labels
2. Add a DNS CNAME record in `hosts/dns1/configuration.nix` (NSD zone data)
3. Deploy DNS: `make nix-deploy-host HOST=dns1 TARGET=10.10.15.15`
4. Deploy containers2: `make nix-deploy-host HOST=containers2 TARGET=10.10.15.11`
5. (Optional) If the service needs external access, add a route in the Cloudflare Zero Trust dashboard (or via `tofu/cloudflare.tf` — see [docs/dns.md](dns.md))
