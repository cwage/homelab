# Hardware

Physical and virtual hardware in the homelab.

## Infrastructure overview

```mermaid
graph TD
    subgraph WAN["WAN (Linode)"]
        felix["felix<br/><small>45.56.113.70</small><br/><small>VPS</small>"]
        gaming1["gaming1<br/><small>45.56.118.89</small><br/><small>Game servers</small>"]
    end

    subgraph CF["Cloudflare"]
        tunnel["Cloudflare Tunnel"]
    end

    internet(("Internet"))

    subgraph LAN["LAN — 10.10.15.0/24"]
        subgraph pve1["pve1 — Proxmox VE (.18)<br/><small>Ryzen 7 1800X · 64 GB · GTX 1050 Ti</small>"]
            dns1["dns1 (.10)<br/><small>1 vCPU · 512 MB</small><br/><small>NSD authoritative DNS</small>"]
            openbao["openbao (.11)<br/><small>1 vCPU · 2 GB</small><br/><small>Secrets management</small>"]
            subgraph containers["containers (.12) — 4 vCPU · 8 GB · GPU passthrough"]
                traefik["Traefik<br/><small>reverse proxy + TLS</small>"]
                jellyfin["Jellyfin<br/><small>media + NVENC</small>"]
                radarr["Radarr"]
                sonarr["Sonarr"]
                sabnzbd["SABnzbd"]
                paperless["Paperless-ngx"]
                owncast["Owncast<br/><small>live streaming</small>"]
                cloudflared["cloudflared"]
            end
        end

        fw1["fw1 (.1)<br/><small>OpenBSD</small><br/><small>pf · DHCP · Unbound · WireGuard</small>"]
        portanas["portanas (.4)<br/><small>Synology DS1815+</small><br/><small>NFS storage</small>"]
    end

    subgraph VPN["WireGuard VPN"]
        vpn_clients["Remote clients<br/><small>(laptop, phone)</small>"]
    end

    internet --> tunnel --> cloudflared
    cloudflared --> jellyfin
    cloudflared --> owncast
    traefik --> jellyfin & radarr & sonarr & sabnzbd & paperless & owncast

    fw1 --- dns1
    fw1 ---|gateway| pve1
    portanas -.-|NFS| containers

    vpn_clients ---|WireGuard| fw1
```

## Physical hosts

### pve1 — Proxmox VE hypervisor

The sole physical server, running Proxmox VE. All local VMs run on this host.

| Component | Spec |
|-----------|------|
| Motherboard | Gigabyte AX370-Gaming-CF (AM4) |
| CPU | AMD Ryzen 7 1800X — 8 cores / 16 threads @ 3.6 GHz |
| Memory | 64 GB DDR4 |
| Boot disk | 250 GB SATA SSD (WD Blue) |
| Data disk | 1 TB SATA HDD (WD Blue) |
| GPU | NVIDIA GeForce GTX 1050 Ti (passed through to containers VM) |
| NIC | Realtek RTL8111 PCIe Gigabit |

### fw1 — OpenBSD firewall

<!-- TODO: document hardware specs -->

Runs OpenBSD. Serves as the LAN gateway, DHCP server, recursive DNS resolver (Unbound), and WireGuard VPN endpoint.

### portanas — Synology NAS

<!-- TODO: document model and drive configuration -->

Synology DS1815+. Provides NFS exports for media, documents, and backups.

## Virtual machines

All VMs run on pve1 and are provisioned via OpenTofu (see `tofu/`). Base image is Debian stable cloud image.

| VM | ID | vCPU | RAM | Disk | Purpose |
|----|-----|------|-----|------|---------|
| **dns1** | 101 | 1 | 512 MB | 8 GB | NSD authoritative DNS |
| **containers** | 102 | 4 | 8 GB | 64 GB | Docker host (Traefik, Jellyfin, arr stack, Paperless, Owncast) |
| **openbao** | 103 | 1 | 2 GB | 20 GB | Secrets management |

The containers VM also has the GTX 1050 Ti passed through for Jellyfin hardware transcoding (NVENC).

## External hosts

| Host | Provider | Purpose |
|------|----------|---------|
| **felix** | Linode | VPS |
| **gaming1** | Linode | Game servers (LinuxGSM) |
