# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible-based infrastructure-as-code repository for managing a homelab environment with Proxmox hosts, OpenBSD firewalls, and Linux VPS instances. All Ansible operations run inside Docker containers for consistent environments across developers.

## Docker-First Workflow

**CRITICAL**: This repository uses Docker Compose exclusively for running Ansible. Never run ansible commands directly on the host.

### Initial Setup

```bash
make init    # Creates .env with your UID/GID
make build   # Builds the Ansible Docker image
make galaxy  # Installs required Ansible collections
```

### Common Commands

All Ansible operations via Makefile targets (runs in containers):

- `make ping` - Test connectivity to all hosts
- `make access_check` - Verify SSH and sudo access
- `make users` - Deploy user configurations
- `make firewall` - Configure OpenBSD firewall (requires `--ask-become-pass`)
- `make felix` - Configure VPS (felix) users
- `make version` - Show Ansible version in container
- `make sh` - Interactive shell inside Ansible container

### Running Custom Playbooks

```bash
make run PLAY=playbooks/your-playbook.yml
make run PLAY=playbooks/your-playbook.yml LIMIT='pve1'
make run PLAY=playbooks/your-playbook.yml EXTRA_VARS='key=value'
```

### Ad-hoc Commands

```bash
make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'
make adhoc HOSTS=fw1 MODULE=ping
```

## Architecture

### Inventory Structure

Three host groups defined in `inventories/hosts.yml`:

1. **proxmox** - Debian-based Proxmox VE hosts
   - `pve1`: 10.10.15.18 (primary hypervisor)

2. **openbsd_firewalls** - OpenBSD firewall/router appliances
   - `fw1`: 10.10.15.1 (primary gateway with WireGuard VPN)

3. **linode_vps** - Remote VPS instances
   - `felix`: 45.56.113.70:5344 (Linode VPS)

### Roles Overview

- **users** - Manages system users with SSH keys, sudo access, secure home directories (0700)
- **openbsd_firewall** - Deploys and validates pf.conf and dhcpd.conf on OpenBSD using `raw` module
- **wireguard_server** - Configures WireGuard VPN on OpenBSD, manages interface and forwarding
- **packages** - Installs standard system packages from `system_packages` variable
- **custom_packages** - Deploys custom .deb packages (e.g., tinyfugue)
- **nginx** - Installs nginx, manages www-data group membership, removes default site
- **system** - Sets hostname, updates /etc/hosts, configures SSH socket

### Playbook-Role Mapping

- `playbooks/users.yml` → `proxmox` hosts → `users` role
- `playbooks/firewall.yml` → `openbsd_firewalls` hosts → `wireguard_server` + `openbsd_firewall` roles
- `playbooks/vps.yml` → `linode_vps` hosts → `users` role
- `playbooks/ping.yml` - Connectivity test
- `playbooks/access_check.yml` - SSH/sudo verification

### Configuration Variables

Group-specific variables in `group_vars/`:

- `group_vars/proxmox.yml` - Defines `managed_users` list with SSH keys, sudo config, groups

User definitions structure:
```yaml
managed_users:
  - name: username
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/username.pub"  # Relative to inventory_dir
```

### OpenBSD Firewall Role Details

The `openbsd_firewall` role uses `ansible.builtin.raw` module exclusively (no Python on OpenBSD):

- Validates pf.conf with `pfctl -nf` before deployment
- Validates dhcpd.conf with `dhcpd -n` before deployment
- Uses handlers to reload services only on config changes
- Templates stored in `roles/openbsd_firewall/templates/`

### SSH Key Management

- Private keys: `keys/deploy/` directory (gitignored)
- Public keys: `keys/deploy.pub` (committed to repo)
- SSH key paths in ansible.cfg: `private_key_file = keys/deploy`
- Users role supports both `ssh_pubkey` (literal string) and `ssh_pubkey_file` (path) formats

### Docker Configuration

- Main container: `ansible` service runs ansible-core 2.16.x in Debian stable-slim
- Network mode: `host` (containers reach LAN hosts directly)
- User mapping: Container runs as your UID/GID (set in .env via `make init`)
- Volumes: Repo mounted at `/work` with SELinux `:Z` label
- Collections installed to: `collections/` directory
- Ansible config: `/work/ansible.cfg` (mounted from repo)

### Special Build: TinyFugue

Separate builder container for compiling tinyfugue .deb package:

```bash
make build-tinyfugue  # Builds .deb into files/packages/
```

## Development Guidelines

### Creating New Roles

Standard Ansible role structure:
```
roles/rolename/
├── tasks/
│   └── main.yml
├── templates/
├── files/
├── defaults/
│   └── main.yml
└── handlers/
    └── main.yml
```

### Adding New Hosts

1. Add host to appropriate group in `inventories/hosts.yml`
2. Create group_vars file if needed: `group_vars/groupname.yml`
3. Test connectivity: `make run PLAY=playbooks/ping.yml LIMIT='newhostname'`

### OpenBSD-Specific Considerations

- Use `ansible.builtin.raw` module (no Python dependency)
- Always validate configs before deployment (`pfctl -nf`, `dhcpd -n`, etc.)
- Use `become: true` sparingly (doas vs sudo)
- Handler triggers for service reloads: `rcctl reload pf`, `rcctl restart dhcpd`

### Testing Changes

1. Use check mode for dry runs: `make run PLAY=playbooks/something.yml OPTS='--check'`
2. Limit to specific hosts: `make run PLAY=playbooks/something.yml LIMIT='hostname'`
3. Increase verbosity: `make run PLAY=playbooks/something.yml OPTS='-vvv'`
4. Test connectivity first: `make ping`

### Become/Sudo Behavior

- Default in `ansible.cfg`: `become = False`
- Playbooks explicitly set `become: true` when needed
- The `deploy` user has passwordless sudo via sudoers.d files
- Firewall playbook requires `--ask-become-pass` for OpenBSD doas

## Security Notes

- Home directories default to 0700 (owner-only access)
- SSH keys managed via ansible.posix.authorized_key module
- Sudoers files validated with `visudo -cf` before deployment
- Host key checking disabled in ansible.cfg (bootstrap convenience - consider enabling later)
- Private keys never committed (keys/ directory in .gitignore)

### CRITICAL: Passwordless Sudo

**NEVER add `sudo_nopasswd: true` to user configurations unless explicitly requested by the user.**

Passwordless sudo is a significant security risk that allows a user account to execute any privileged command without authentication. This should only be granted:
- For automated service accounts (like `deploy`)
- When explicitly requested by the user
- Never as a default or "assumed" configuration

When adding or modifying user accounts:
1. Check existing configurations for `sudo_nopasswd` settings
2. Preserve the existing security posture (e.g., comments indicating passwordless sudo is NOT desired)
3. Only modify security-sensitive settings when explicitly instructed
4. If uncertain, ask the user before granting elevated privileges
