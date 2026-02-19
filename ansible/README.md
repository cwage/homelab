# ansible — host configuration

Ansible roles and playbooks for configuring all homelab hosts: Proxmox hypervisor, OpenBSD firewall, DNS server, Docker container host, NAS, and VPS instances. All operations run inside Docker containers.

## Setup

Ansible reads credentials from the root `.env` file (shared with OpenTofu). See the root [README](../README.md) getting-started section for initial `.env` setup.

```bash
make init          # set UID/GID in .env for Docker user mapping
make build         # build the Ansible Docker image
make galaxy        # install required Ansible collections
make ping          # test connectivity to all hosts
```

### SSH keys

Two separate key directories:

- **`keys/`** — Deploy key for Ansible automation (`keys/deploy` private, `keys/deploy.pub` public). The private key is gitignored.
- **`inventories/keys/`** — User SSH public keys deployed to hosts via the `users` role.

## Common commands

```bash
make ping                     # test connectivity
make firewall                 # configure fw1 (pf, DHCP, Unbound, WireGuard)
make firewall-check           # dry-run firewall
make dns                      # configure dns1 (NSD)
make containers               # configure containers host (Docker, GPU, certs, stacks)
make proxmox                  # configure pve1 (users, NFS mounts)
make felix                    # configure VPS
make gaming                   # provision game servers
make all                      # apply all standard playbooks (use sparingly)
make run PLAY=playbooks/firewall.yml LIMIT=fw1 OPTS="--check --diff"
make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'
make sh                       # interactive shell in Ansible container
```

Run `make help` for the full list.

## Inventory

Hosts and groups defined in `inventories/hosts.yml`. Group variables in `inventories/group_vars/`, host-specific overrides in `inventories/host_vars/`.

| Group | Hosts | Playbook |
|-------|-------|----------|
| `proxmox` | pve1 | `playbooks/proxmox.yml` |
| `openbsd_firewalls` | fw1 | `playbooks/firewall.yml` |
| `dns_servers` | dns1 | `playbooks/dns.yml` |
| `container_hosts` | containers | `playbooks/containers.yml` |
| `openbao` | openbao | `playbooks/openbao.yml` |
| `linode_vps` | felix | `playbooks/vps.yml` |
| `gaming_servers` | gaming1 | `playbooks/gaming.yml` |

`portanas` (Synology NAS) is a standalone host managed via `playbooks/nas.yml`.

## Roles

| Role | Description |
|------|-------------|
| `users` | System users, SSH keys, sudo, home directories |
| `openbsd_firewall` | pf, dhcpd, unbound, resolv.conf (OpenBSD, raw module) |
| `wireguard_server` | WireGuard VPN on OpenBSD |
| `nsd` | NSD authoritative DNS server |
| `docker_host` | Docker + Compose installation |
| `gpu_passthrough` | VFIO/IOMMU on Proxmox for PCI passthrough |
| `nvidia_container` | NVIDIA driver + container toolkit |
| `dns_client` | /etc/resolv.conf configuration |
| `packages` | System packages from variable list |
| `custom_packages` | Custom .deb packages (tinyfugue) |
| `nfs_mounts` | Client-side NFS mount configuration |
| `synology_nfs` | Manage NFS shares on Synology DSM via SSH |
| `proxmox_certs` | Deploy wildcard TLS cert to Proxmox |
| `nginx` | Install nginx, manage www-data group |
| `hostname` | Set hostname and /etc/hosts |
| `system` | Hostname, /etc/hosts, SSH socket config |
| `gaming_server` | LinuxGSM game server management |
| `openbao` | Install/configure OpenBao |
| `pve_template` | Build Proxmox VM templates |

## Docker workflow

The Ansible container runs with `network_mode: host` so it can reach LAN hosts directly. It mounts the repo at `/work` and passes through OpenBao credentials from the root `.env` via `--env-file`.

```bash
make build            # rebuild the container image
make version          # show Ansible version in container
make sh               # interactive shell for debugging
```

## Secret scanning

```bash
make trufflehog       # scan ansible/ tree for leaked secrets
```

## OpenBSD notes

The `openbsd_firewall` and `wireguard_server` roles use `ansible.builtin.raw` exclusively since OpenBSD doesn't have Python. Configs are validated before deployment (`pfctl -nf`, `dhcpd -n`, `nsd-checkconf`) and services are reloaded via handlers.
