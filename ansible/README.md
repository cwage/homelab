# Homelab Ansible

Ansible configuration management for homelab infrastructure including OpenBSD firewalls, Proxmox hosts, VPS, and NAS devices.

## Documentation

- **[Getting Started Guide](../docs/getting-started.md)** — Complete setup instructions
- **[Inventory Guide](docs/inventory-guide.md)** — Configuring hosts and variables
- **[Role Documentation](roles/)** — See individual role READMEs

## Overview

This component manages the configuration of all hosts in the homelab. All operations run via Docker — no local Ansible installation required.

**Managed hosts:**
- Proxmox VE servers (Debian-based)
- OpenBSD firewalls (PF, DHCP, DNS, WireGuard)
- Linux VPS (web servers, applications)
- Synology NAS (NFS shares)

## Quick Reference

### Common Commands

```bash
make init              # Initialize .env file with UID/GID
make build             # Build Ansible Docker image
make ping              # Test connectivity to all hosts
make users             # Apply user management
make firewall          # Configure OpenBSD firewall (PF, DHCP, DNS)
make templates         # Build Proxmox VM templates
make felix             # Configure VPS
make nas               # Configure Synology NAS
```

Add `-check` suffix for dry-run mode:
```bash
make firewall-check    # Preview firewall changes (no modifications)
make users-check       # Preview user changes
```

See `make help` for complete list of targets.

## Initial Setup

**For detailed setup instructions, see [Getting Started Guide](../docs/getting-started.md).**

### 1. Initialize Environment

```bash
make init
```

Creates `.env` and sets your UID/GID for proper Docker permissions.

### 2. Build Container

```bash
make build
```

Builds the Ansible Docker image with all required collections.

### 3. SSH Key Setup

Generate SSH keys for the deploy user:

```bash
mkdir -p keys/deploy
ssh-keygen -t ed25519 -f keys/deploy/id_ed25519 -C "ansible-deploy" -N ""
chmod 600 keys/deploy/id_ed25519

# Copy to target hosts
ssh-copy-id -i keys/deploy/id_ed25519.pub deploy@<host-ip>

# Create symlink for templates
cd keys
ln -s deploy/id_ed25519.pub deploy.pub
```

See [Getting Started Guide](../docs/getting-started.md) for creating the deploy user on target hosts.

### 4. Configure Inventory

Edit `inventories/hosts.yml` to match your infrastructure:

```yaml
all:
  children:
    proxmox:
      hosts:
        pve1:
          ansible_host: 10.10.15.18
          ansible_port: 22
```

See [Inventory Guide](docs/inventory-guide.md) for details.

### 5. Test Connectivity

```bash
make ping
```

Expected: Green `pong` responses from all hosts.

## Configuration

### Inventory Structure

```
inventories/
├── hosts.yml          # Host definitions
├── group_vars/        # Variables per group
│   ├── all.yml
│   ├── proxmox.yml
│   └── openbsd_firewalls.yml
└── host_vars/         # Variables per host
    ├── pve1.yml
    └── fw1.yml
```

See [Inventory Guide](docs/inventory-guide.md) for complete documentation.

### Ansible Configuration

Configured in `ansible.cfg`:
- Remote user: `deploy`
- Private key: `keys/deploy/id_ed25519`
- Inventory: `inventories/hosts.yml`
- Host key checking: Disabled (for bootstrap convenience)

## Available Playbooks

- `playbooks/ping.yml` — Test connectivity
- `playbooks/access_check.yml` — Verify SSH and sudo access
- `playbooks/users.yml` — Manage user accounts
- `playbooks/firewall.yml` — Configure OpenBSD firewall (PF, DHCP, DNS, WireGuard)
- `playbooks/pve-templates.yml` — Build Proxmox VM templates
- `playbooks/vps.yml` — Configure VPS (felix)
- `playbooks/nas.yml` — Configure Synology NAS

## Available Roles

Each role has comprehensive documentation in its directory:

- [openbsd_firewall](roles/openbsd_firewall/README.md) — PF, DHCP, Unbound DNS
- [wireguard_server](roles/wireguard_server/README.md) — WireGuard VPN server
- [synology_nfs](roles/synology_nfs/README.md) — NFS share management
- [users](roles/users/README.md) — User account management
- [system](roles/system/README.md) — Hostname, SSH configuration
- [packages](roles/packages/README.md) — System package installation
- [custom_packages](roles/custom_packages/README.md) — Custom .deb packages
- [nginx](roles/nginx/README.md) — Web server configuration
- [pve_template](roles/pve_template/README.md) — VM template creation

## Docker Container Details

All operations run in a Docker container:
- Base image: Python with Ansible
- Volume mount: `./:/work:Z` (with SELinux support)
- Working directory: `/work`
- Ansible configuration: Loaded from `ansible.cfg`
- SSH keys: Mounted from `keys/`

**SELinux note:** The docker-compose volume uses `:Z` which relabels the bind mount for SELinux systems (Fedora/RHEL). Ignored on non-SELinux hosts.

## Advanced Usage

### Run Arbitrary Playbook

```bash
make run PLAY=playbooks/custom.yml
```

With options:
```bash
make run PLAY=playbooks/users.yml LIMIT=pve1 OPTS="--check --diff"
```

### Ad-Hoc Commands

```bash
# Run shell command
make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'

# Use raw module (no Python required, for OpenBSD)
make adhoc HOSTS=fw1 MODULE=raw ARGS='pfctl -sr'
```

### Interactive Shell

```bash
make sh
# Now inside container with ansible-playbook, ansible, etc.
```

### Install Collections

```bash
make galaxy
```

Installs Ansible collections from `requirements.yml` into `collections/`.

## Secret Scanning

TruffleHog runs in Docker to scan for accidentally committed secrets.

### One-off Scan

```bash
make trufflehog
```

Uses root-level scanner that excludes known safe paths (like `keys/`).

### Pre-commit Hook

Install at repository root:
```bash
cd ..
make install-precommit-hook
```

After installation, every `git commit` runs TruffleHog automatically. Bypass temporarily with:
```bash
SKIP_TRUFFLEHOG=1 git commit -m "message"
```

## Troubleshooting

See [Getting Started Guide](../docs/getting-started.md) for common issues and solutions.

**Quick checks:**
```bash
# Test SSH connectivity
ssh -i keys/deploy/id_ed25519 deploy@<host-ip>

# Verify ansible can reach hosts
make ping

# Check sudo access
make access_check

# View inventory configuration
ansible-inventory --host <hostname> --yaml
```

## Related Documentation

- [Getting Started Guide](../docs/getting-started.md) — Complete setup walkthrough
- [Inventory Guide](docs/inventory-guide.md) — Host and variable configuration
- [Root README](../README.md) — Repository overview and make targets
