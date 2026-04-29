# homelab

Infrastructure-as-code monorepo for a home network running on Proxmox VE, managed with OpenTofu (VM provisioning) and Ansible (host configuration). Everything runs in Docker containers — no local tool installs required beyond Docker and Make.

## Architecture

### Network and hosts

The LAN is `10.10.15.0/24` under the domain `lan.quietlife.net`. A couple of external Linode VPS instances live outside the LAN. See [docs/hardware.md](docs/hardware.md) for a full infrastructure diagram and hardware specs.

| Host | IP | Role |
|------|----|------|
| **pve1** | 10.10.15.18 | Proxmox VE hypervisor — runs all local VMs |
| **fw1** | 10.10.15.1 | OpenBSD firewall/router — pf, DHCP, Unbound (recursive DNS), WireGuard VPN |
| **dns1** | 10.10.15.15 | NSD authoritative DNS for `lan.quietlife.net` (NixOS) |
| **bao2** | 10.10.15.16 | Secrets management (OpenBao, a HashiCorp Vault fork; NixOS) |
| **containers2** | 10.10.15.11 | Docker host (NixOS) — [Traefik, Jellyfin, arr stack, Paperless](docs/services.md), GPU passthrough |
| **portanas** | 10.10.15.4 | Synology NAS — NFS storage backing media, documents, and [backups](backup/README.md) |
| **felix** | 45.56.113.70 | Linode VPS |
| **gaming1** | 45.56.118.89 | Linode VPS — LinuxGSM game servers |

### Two-layer IaC

```
OpenTofu (tofu/)              Ansible (ansible/)            NixOS (flake.nix, modules/)
─────────────────             ──────────────────            ───────────────────────────
Provisions VMs on Proxmox  →  Configures hosts: packages,  Declarative host config for
(cpu, memory, disk, network,  users, firewall rules, DNS,  Proxmox VMs (replaces Ansible
cloud-init, GPU passthrough)  services, Docker stacks       for NixOS hosts over time)
```

OpenTofu creates the VMs, Ansible configures everything that runs on them. NixOS configurations (built via a Dockerized Nix builder) are being introduced for Proxmox VMs, starting with a base template. All three stacks have Makefiles that run all commands inside Docker containers, so the workflow is the same regardless of what workstation you're on.

### Secrets and TLS

Secrets (API tokens, deploy keys, TLS certs) are stored in OpenBao and fetched at deploy time via the `community.hashi_vault` Ansible collection. A wildcard Let's Encrypt cert for `*.lan.quietlife.net` is managed via the `lego/` tooling and deployed to Traefik and Proxmox. See [docs/openbao.md](docs/openbao.md), [docs/openbao-secrets.md](docs/openbao-secrets.md), and [docs/tls-certificates.md](docs/tls-certificates.md).

### Backups

NAS data is backed up to Backblaze B2 via a Dockerized rclone container with encrypted remotes. See [backup/README.md](backup/README.md).

## Repository layout

```
├── flake.nix         NixOS entry point — host definitions and image builds
├── hosts/            Per-host NixOS configurations
├── modules/          Shared NixOS modules (base config, openbao-agent, etc.)
├── nix/              Dockerized Nix builder for Proxmox VMA images
├── openbao/          Dockerized OpenBao CLI tooling (AppRole management)
├── ansible/          Host configuration for non-NixOS hosts (firewall, Proxmox, VPS, NAS, gaming)
│   ├── playbooks/    Per-host-group playbooks (firewall.yml, proxmox.yml, vps.yml, etc.)
│   ├── roles/        Reusable roles (openbsd_firewall, wireguard_server, etc.)
│   └── inventories/  Host definitions and group variables
├── tofu/             OpenTofu VM definitions for Proxmox
├── backup/           Workstation-level rclone shell (production scheduler is in modules/backups.nix)
├── lego/             Let's Encrypt certificate management (lego CLI)
├── docs/             Design notes, runbooks, and operational guides
└── scripts/          Repo-level utility scripts
```

## Getting started

### Prerequisites

- Docker and Docker Compose
- GNU Make
- SSH access to the target hosts (deploy key in `ansible/keys/`)

### First-time setup

```bash
# Clone the repo
git clone git@github.com:cwage/homelab.git && cd homelab

# Create root .env from the example and fill in your credentials
cp .env.example .env
# Edit .env — at minimum set BAO_ADDR and BAO_TOKEN (required for Ansible
# to fetch secrets from OpenBao). See docs/openbao-secrets.md for token setup.
# Proxmox API credentials are also defined here (required for OpenTofu).

# Ansible setup
cd ansible
make init          # sets UID/GID in .env for Docker user mapping
make build         # builds the Ansible Docker image
make galaxy        # installs Ansible collections
make ping          # test connectivity to all hosts
cd ..

# OpenTofu setup (if provisioning VMs)
cd tofu
make build         # builds the Tofu Docker image
make plan          # preview what Tofu would do
cd ..
```

### Day-to-day workflow

All operations go through Make targets at the repo root. The root Makefile delegates to component Makefiles:

```bash
make ansible-<target>     # runs target in ansible/Makefile
make tofu-<target>        # runs target in tofu/Makefile
```

Use `make ansible-help` and `make tofu-help` to list all available targets.

## Make targets

### Ansible (host configuration)

```bash
make ansible-ping             # test connectivity to all hosts
make ansible-firewall         # apply firewall config (pf, DHCP, Unbound, WireGuard)
make ansible-firewall-check   # dry-run firewall
make ansible-proxmox          # configure Proxmox host (users, NFS mounts)
make ansible-felix            # configure Linode VPS
make ansible-felix-check      # dry-run VPS config
make ansible-gaming           # provision game servers
make ansible-all              # apply all standard playbooks (use sparingly)
make ansible-check-all        # dry-run all standard playbooks
make ansible-run PLAY=playbooks/firewall.yml LIMIT=fw1 OPTS="--check --diff"
```

### OpenTofu (VM provisioning)

```bash
make tofu-plan       # show what Tofu would change
make tofu-apply      # apply changes (create/modify VMs)
make tofu-shell      # interactive shell in Tofu container
```

### NixOS (Proxmox image builder and host deployment)

```bash
make nix-build      # build the Nix Docker image
make nix-template   # build NixOS Proxmox VMA template image (outputs to nix/output/)
make nix-deploy     # upload VMA to Proxmox, restore as VMID 9001, convert to template
make nix-deploy-host HOST=<name> [TARGET=<ip>]  # build and deploy NixOS config to a remote host
make nix-shell      # interactive shell in Nix container
make nix-clean      # remove Docker resources and build output
```

### OpenBao (secrets management CLI)

```bash
make openbao-approle-enable                              # enable AppRole auth + create nixos-host policy (one-time)
make openbao-approle-create-role NAME=dns1 IP=10.10.15.15  # create CIDR-bound role for a NixOS host
make openbao-approle-show-role NAME=dns1                 # show role_id for a host
make openbao-approle-list                                # list all AppRole roles
make openbao-shell                                       # interactive bao CLI shell
```

### Security scanning

```bash
make trufflehog              # scan entire repo for leaked secrets
make ansible-trufflehog      # scan ansible/ tree only
make tofu-trufflehog         # scan tofu/ tree only
make install-precommit-hook  # install trufflehog pre-commit hook
```

## Secrets and local state

- Root `.env` (gitignored): OpenBao credentials (BAO_ADDR, BAO_TOKEN) and Proxmox API credentials — shared by both Ansible and OpenTofu via `--env-file`
- Ansible deploy keys: `ansible/keys/` (gitignored)
- Tofu state: stored on NAS via NFS (not in git — see `TOFU_STATE_PATH` in `.env`)

## Documentation

| Document | Description |
|----------|-------------|
| [docs/services.md](docs/services.md) | Container services inventory, URLs, and deployment |
| [docs/hardware.md](docs/hardware.md) | Physical and virtual hardware specs |
| [docs/tls-certificates.md](docs/tls-certificates.md) | Wildcard cert lifecycle: Let's Encrypt → OpenBao → Traefik/Proxmox |
| [docs/adding-vm.md](docs/adding-vm.md) | Step-by-step guide to adding a new VM |
| [docs/dns.md](docs/dns.md) | DNS setup: internal (NSD + Unbound) and external (Cloudflare) |
| [docs/openbao.md](docs/openbao.md) | OpenBao operations: deploy, unseal, certs, backups |
| [docs/openbao-secrets.md](docs/openbao-secrets.md) | KV secrets structure, policies, token management |
| [docs/gpu-passthrough.md](docs/gpu-passthrough.md) | GPU passthrough setup on Proxmox |
| [docs/pve-templates.md](docs/pve-templates.md) | Proxmox VM templates: NixOS (9001) and Debian (9000) — what's baked in, how to build, which to use |
| [docs/gaming-servers.md](docs/gaming-servers.md) | Game server provisioning and operations |
| [backup/README.md](backup/README.md) | NAS → Backblaze B2 backup system |
| [ansible/README.md](ansible/README.md) | Ansible-specific setup and workflow |
| [ansible/roles/wireguard_server/README.md](ansible/roles/wireguard_server/README.md) | WireGuard VPN setup and client configuration |
| [docs/nixos-migration.md](docs/nixos-migration.md) | NixOS migration: pipeline, AppRole secrets, per-host walkthrough |
| [tofu/README.md](tofu/README.md) | OpenTofu-specific setup and workflow |
