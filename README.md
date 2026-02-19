# homelab

Infrastructure-as-code monorepo for a home network running on Proxmox VE, managed with OpenTofu (VM provisioning) and Ansible (host configuration). Everything runs in Docker containers — no local tool installs required beyond Docker and Make.

## Architecture

### Network and hosts

The LAN is `10.10.15.0/24` under the domain `lan.quietlife.net`. A couple of external Linode VPS instances live outside the LAN.

| Host | IP | Role |
|------|----|------|
| **pve1** | 10.10.15.18 | Proxmox VE hypervisor — runs all local VMs |
| **fw1** | 10.10.15.1 | OpenBSD firewall/router — pf, DHCP, Unbound (recursive DNS), WireGuard VPN |
| **dns1** | 10.10.15.10 | NSD authoritative DNS for `lan.quietlife.net` |
| **openbao** | 10.10.15.11 | Secrets management (OpenBao, a HashiCorp Vault fork) |
| **containers** | 10.10.15.12 | Docker host for containerized apps, GPU passthrough (GTX 1050 Ti) |
| **portanas** | 10.10.15.4 | Synology NAS — storage, NFS exports |
| **felix** | 45.56.113.70 | Linode VPS |
| **gaming1** | 45.56.118.89 | Linode VPS — LinuxGSM game servers |

### Two-layer IaC

```
OpenTofu (tofu/)              Ansible (ansible/)
─────────────────             ──────────────────
Provisions VMs on Proxmox  →  Configures hosts: packages,
(cpu, memory, disk, network,  users, firewall rules, DNS,
cloud-init, GPU passthrough)  services, Docker stacks, certs
```

OpenTofu creates the VMs, Ansible configures everything that runs on them. Both are wrapped in Dockerized Makefiles so the workflow is the same regardless of what workstation you're on.

### Secrets

Secrets (API tokens, deploy keys, TLS certs) are stored in OpenBao and fetched at deploy time via the `community.hashi_vault` Ansible collection. See [docs/openbao.md](docs/openbao.md) and [docs/openbao-secrets.md](docs/openbao-secrets.md).

## Repository layout

```
├── ansible/          Host configuration (roles, playbooks, inventories)
│   ├── playbooks/    Per-host-group playbooks (firewall.yml, dns.yml, etc.)
│   ├── roles/        Reusable roles (openbsd_firewall, docker_host, nsd, etc.)
│   └── inventories/  Host definitions and group variables
├── tofu/             OpenTofu VM definitions for Proxmox
├── backup/           Dockerized NAS → Backblaze B2 backup tooling
├── lego/             Let's Encrypt certificate management (lego CLI)
├── docs/             Design notes, runbooks, and operational guides
├── testing/          Resume preview container
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

# Ansible setup
cd ansible
make init          # creates .env with your UID/GID
make build         # builds the Ansible Docker image
make galaxy        # installs Ansible collections
make ping          # test connectivity to all hosts
cd ..

# OpenTofu setup (if provisioning VMs)
cd tofu
cp .env.example .env   # add Proxmox API credentials
make build             # builds the Tofu Docker image
make plan              # preview what Tofu would do
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
make ansible-dns              # apply NSD authoritative DNS config
make ansible-containers       # configure Docker host (packages, GPU, certs, stacks)
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

### Security scanning

```bash
make trufflehog              # scan entire repo for leaked secrets
make ansible-trufflehog      # scan ansible/ tree only
make tofu-trufflehog         # scan tofu/ tree only
make install-precommit-hook  # install trufflehog pre-commit hook
```

## Secrets and local state

- OpenTofu API credentials: `tofu/.env` (gitignored)
- Ansible deploy keys: `ansible/keys/` (gitignored)
- OpenBao token/address: `ansible/.env` (gitignored)
- Tofu state: `tofu/terraform.tfstate` (tracked in git — single-developer workflow)

## Documentation

| Document | Description |
|----------|-------------|
| [docs/adding-vm.md](docs/adding-vm.md) | Step-by-step guide to adding a new VM |
| [docs/dns-plan.md](docs/dns-plan.md) | DNS architecture: NSD + Unbound design |
| [docs/openbao.md](docs/openbao.md) | OpenBao operations: deploy, unseal, certs, backups |
| [docs/openbao-secrets.md](docs/openbao-secrets.md) | KV secrets structure, policies, token management |
| [docs/gpu-passthrough.md](docs/gpu-passthrough.md) | GPU passthrough setup on Proxmox |
| [docs/pve-templates.md](docs/pve-templates.md) | Building Proxmox VM templates |
| [docs/gaming-servers.md](docs/gaming-servers.md) | Game server provisioning and operations |
| [docs/resume-preview.md](docs/resume-preview.md) | Resume preview container workflow |
| [backup/README.md](backup/README.md) | NAS → Backblaze B2 backup system |
| [ansible/README.md](ansible/README.md) | Ansible-specific setup and workflow |
| [tofu/README.md](tofu/README.md) | OpenTofu-specific setup and workflow |
