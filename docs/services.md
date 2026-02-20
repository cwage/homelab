# Services

All self-hosted services run as Docker containers on the **containers** host (`10.10.15.12`), managed via a single `docker-compose.yml` deployed by Ansible. Traefik handles reverse proxying and TLS termination with a wildcard certificate for `*.lan.quietlife.net`.

## Service inventory

| Service | Image | Internal URL | Purpose |
|---------|-------|-------------|---------|
| **Traefik** | `traefik:v2.11` | `https://traefik.lan.quietlife.net` | Reverse proxy, TLS termination, dashboard |
| **Jellyfin** | `linuxserver/jellyfin` | `https://jellyfin.lan.quietlife.net` | Media server (NVENC GPU transcoding) |
| **Radarr** | `linuxserver/radarr` | `https://radarr.lan.quietlife.net` | Movie automation |
| **Sonarr** | `linuxserver/sonarr` | `https://sonarr.lan.quietlife.net` | TV automation |
| **SABnzbd** | `linuxserver/sabnzbd` | `https://sabnzbd.lan.quietlife.net` | Usenet download client |
| **Paperless-ngx** | `paperless-ngx/paperless-ngx` | `https://paperless.lan.quietlife.net` | Document management |
| **Owncast** | `owncast/owncast` | `https://owncast.lan.quietlife.net` | Live streaming (RTMP ingest on port 1935) |
| **Cloudflared** | `cloudflare/cloudflared` | — | Cloudflare Tunnel for external access |
| **Paperless Redis** | `redis` | — | Backend for Paperless-ngx |

## External access

Jellyfin and Owncast are exposed externally via a Cloudflare Tunnel (`cloudflared` container). The tunnel token is stored in OpenBao at `kv/infra/cloudflare/tunnel`. External URLs are configured in the Cloudflare Zero Trust dashboard.

## How it fits together

```
Internet → Cloudflare Tunnel → cloudflared container ─┐
                                                       ↓
LAN clients → fw1 (DNS) → containers:443 → Traefik → service containers
                                              ↑
                                     wildcard TLS cert
                                   (see docs/tls-certificates.md)
```

- **DNS**: Each service has a CNAME record in the NSD zone pointing to `containers.lan.quietlife.net`
- **TLS**: Traefik serves a wildcard cert for `*.lan.quietlife.net` (see [docs/tls-certificates.md](tls-certificates.md))
- **Storage**: Jellyfin, Radarr, Sonarr, and SABnzbd share `/mnt/nas/Media` (NFS from NAS). Paperless uses `/mnt/nas/paperless`.

## NFS mounts

The containers host mounts NAS shares under `/mnt/nas/`:

| Mount | NAS share | Used by |
|-------|-----------|---------|
| `/mnt/nas/Media` | `portanas:/volume1/Media` | Jellyfin, Radarr, Sonarr, SABnzbd |
| `/mnt/nas/paperless` | `portanas:/volume1/paperless` | Paperless-ngx |

Additional NAS shares are mounted read-only for backup access. See `ansible/roles/nfs_mounts/` for the full list.

## Deployment

```bash
make ansible-containers       # full deploy (packages, GPU, certs, NFS, stacks)
make ansible-containers-check # dry-run
```

The `containers.yml` playbook handles:
1. System packages and Docker installation
2. NVIDIA driver and container toolkit (GPU passthrough)
3. NFS mount configuration
4. Wildcard TLS cert retrieval from OpenBao → `/opt/stacks/certs/`
5. Docker Compose stack deployment to `/opt/stacks/`

## Adding a new service

1. Add the service to `ansible/files/stacks/docker-compose.yml` with Traefik labels
2. Add a DNS CNAME record in `ansible/roles/nsd/templates/lan.quietlife.net.zone.j2`
3. Deploy DNS: `make ansible-dns`
4. Deploy containers: `make ansible-containers`
5. (Optional) If the service needs external access, add a route in the Cloudflare Zero Trust dashboard
