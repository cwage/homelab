# Homelab Documentation

Complete documentation for the homelab infrastructure monorepo.

## Getting Started

**New to this repository?** Start here:
- **[Getting Started Guide](getting-started.md)** — Complete setup walkthrough including prerequisites, initial setup, SSH keys, and first runs

## Component Documentation

### Ansible (Configuration Management)
- **[Ansible README](../ansible/README.md)** — Overview and quick reference
- **[Inventory Guide](../ansible/docs/inventory-guide.md)** — Configuring hosts and variables
- **[Role Documentation](../ansible/roles/)** — See individual role READMEs

### OpenTofu (VM Provisioning)
- **[OpenTofu README](../tofu/README.md)** — Overview and quick reference
- **[Variables Guide](../tofu/docs/variables-guide.md)** — Configuration reference

## Architecture and Design

- **[DNS Plan](dns-plan.md)** — Authoritative DNS and DHCP architecture for `lan.quietlife.net`
- **[PVE Templates](pve-templates.md)** — VM template creation workflow

## Ansible Roles

Comprehensive documentation for each role:

### Infrastructure
- [openbsd_firewall](../ansible/roles/openbsd_firewall/README.md) — PF firewall, DHCP, and Unbound DNS on OpenBSD
- [wireguard_server](../ansible/roles/wireguard_server/README.md) — WireGuard VPN server on OpenBSD
- [pve_template](../ansible/roles/pve_template/README.md) — Proxmox VM template creation

### System Configuration
- [users](../ansible/roles/users/README.md) — User account management and SSH keys
- [system](../ansible/roles/system/README.md) — Hostname and SSH port configuration
- [packages](../ansible/roles/packages/README.md) — System package installation via APT
- [custom_packages](../ansible/roles/custom_packages/README.md) — Custom-built .deb package deployment

### Services
- [nginx](../ansible/roles/nginx/README.md) — Nginx web server with virtual hosts and basic auth
- [synology_nfs](../ansible/roles/synology_nfs/README.md) — NFS share management on Synology NAS

## Quick Reference

### Common Commands

**Ansible:**
```bash
make ansible-ping          # Test connectivity
make ansible-users         # Manage users
make ansible-firewall      # Configure firewall
make ansible-templates     # Build VM templates
make ansible-felix         # Configure VPS
make ansible-nas           # Configure NAS
```

**OpenTofu:**
```bash
make tofu-init      # Initialize
make tofu-plan      # Preview changes
make tofu-apply     # Apply changes
make tofu-shell     # Interactive shell
```

**Security:**
```bash
make trufflehog              # Scan for secrets
make install-precommit-hook  # Install git hook
```

See [Getting Started Guide](getting-started.md) for detailed usage.

## Repository Structure

```
homelab/
├── ansible/              # Configuration management
│   ├── inventories/     # Host definitions and variables
│   ├── playbooks/       # Ansible playbooks
│   ├── roles/           # Ansible roles
│   └── docs/            # Ansible-specific docs
├── tofu/                # VM provisioning
│   ├── *.tf             # OpenTofu configuration
│   └── docs/            # OpenTofu-specific docs
├── docs/                # Shared documentation (you are here)
│   ├── README.md        # This file
│   ├── getting-started.md      # Complete setup guide
│   ├── dns-plan.md             # DNS architecture
│   └── pve-templates.md        # Template workflow
└── README.md            # Repository root README
```

## Documentation Conventions

### File Organization
- **Root docs/** — Shared architecture and getting started guides
- **Component docs/** — Component-specific guides (ansible/docs/, tofu/docs/)
- **Role READMEs** — Located in each role directory

### Documentation Structure

Each role README follows this structure:
1. **Purpose** — What the role does
2. **Requirements** — Prerequisites and dependencies
3. **Role Variables** — Configuration options
4. **Example Usage** — Playbook examples
5. **What This Role Does** — Step-by-step explanation
6. **Outputs** — What gets created/configured
7. **Assumptions and Limitations** — Important constraints
8. **Common Issues** — Troubleshooting
9. **Related Documentation** — Cross-references

## Contributing to Documentation

When adding or updating documentation:
- Follow existing structure and style
- Include practical examples
- Document all variables and their defaults
- Add troubleshooting sections for common issues
- Cross-reference related documentation
- Keep examples aligned with actual code

## Getting Help

If documentation doesn't answer your question:
1. Check role-specific READMEs
2. Review playbook outputs with verbose mode (`-vvv`)
3. Search for similar issues in the repository
4. Verify your configuration matches examples
