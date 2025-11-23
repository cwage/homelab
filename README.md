# homelab

Homelab infrastructure monorepo for managing servers, VMs, and network devices using Infrastructure as Code.

## Components

- **`ansible/`** — Configuration management (Ansible)
  - Manages OpenBSD firewalls, Proxmox hosts, VPS, and NAS
  - Handles user accounts, services, and system configuration
  - [Ansible Documentation →](ansible/README.md)
  
- **`tofu/`** — VM provisioning (OpenTofu/Terraform)
  - Provisions VMs on Proxmox VE
  - Downloads and manages cloud images
  - [OpenTofu Documentation →](tofu/README.md)
  
- **`docs/`** — Architecture and design documentation
  - [Getting Started Guide](docs/getting-started.md) — **Start here!**
  - [DNS Architecture](docs/dns-plan.md) — Network design
  - [VM Templates](docs/pve-templates.md) — Template creation workflow

## Quick Start

**New to this repository?** Start with the [Getting Started Guide](docs/getting-started.md) for complete setup instructions.

### Prerequisites

- Docker and Docker Compose (all operations run in containers)
- Make (command wrapper)
- SSH access to managed hosts

### Fast Track

```bash
# Clone repository
git clone https://github.com/cwage/homelab.git
cd homelab

# Set up Ansible
cd ansible
make init      # Create .env file
make build     # Build Docker image
make ping      # Test connectivity

# Set up OpenTofu (if provisioning VMs)
cd ../tofu
cp .env.example .env  # Edit with your Proxmox credentials
make build            # Build Docker image
make init             # Initialize OpenTofu
make plan             # Preview changes
```

See [Getting Started Guide](docs/getting-started.md) for detailed instructions.

## Make Targets

The repository uses Make to wrap Docker-based workflows. All commands run in containers — no local Ansible or OpenTofu installation required.

### Root-Level Commands

- `make ansible-<target>` — Run Ansible target from repo root (see `make ansible-help`)
- `make tofu-<target>` — Run OpenTofu target from repo root (see `make tofu-help`)
- `make ansible` or `make tofu` — Drop into component directory for interactive use
- `make trufflehog` — Scan entire repo for secrets (security)
- `make install-precommit-hook` — Install pre-commit hook for secret scanning

### Ansible Commands

```bash
make ansible-ping          # Test connectivity to all hosts
make ansible-users         # Apply user management
make ansible-firewall      # Configure OpenBSD firewall
make ansible-templates     # Build Proxmox VM templates
make ansible-felix         # Configure VPS
make ansible-nas           # Configure Synology NAS
make ansible-all           # Run all standard playbooks (careful!)
```

Add `-check` suffix for dry-run mode:
```bash
make ansible-firewall-check  # Preview firewall changes
make ansible-check-all       # Dry-run all playbooks
```

### OpenTofu Commands

```bash
make tofu-init      # Initialize OpenTofu
make tofu-plan      # Preview infrastructure changes
make tofu-apply     # Apply changes to Proxmox
make tofu-shell     # Interactive shell in container
make tofu-validate  # Validate configuration
```

### Advanced Usage

```bash
# Run specific playbook with options
make ansible-run PLAY=playbooks/firewall.yml LIMIT=fw1 OPTS="--check --diff"

# Run ad-hoc command
make ansible-adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'

# Component-specific secret scanning
make ansible-trufflehog
make tofu-trufflehog
```

## Repository Structure

```
homelab/
├── ansible/              # Configuration management
│   ├── inventories/     # Host and group definitions
│   ├── playbooks/       # Ansible playbooks
│   ├── roles/           # Ansible roles (see individual READMEs)
│   ├── docs/            # Ansible-specific documentation
│   └── README.md        # Ansible usage guide
├── tofu/                # VM provisioning
│   ├── *.tf             # OpenTofu configuration files
│   ├── docs/            # OpenTofu-specific documentation
│   └── README.md        # OpenTofu usage guide
├── docs/                # Shared documentation
│   ├── getting-started.md   # Complete setup guide (start here!)
│   ├── dns-plan.md          # DNS/DHCP architecture
│   └── pve-templates.md     # VM template workflow
└── Makefile             # Root-level command wrapper
```

## Documentation

### Getting Started
- **[Getting Started Guide](docs/getting-started.md)** — Complete setup walkthrough for new users

### Component Documentation
- **[Ansible README](ansible/README.md)** — Ansible usage and workflows
  - [Inventory Guide](ansible/docs/inventory-guide.md) — Configuring hosts and variables
  - [Role Documentation](ansible/roles/) — See individual role READMEs
- **[OpenTofu README](tofu/README.md)** — OpenTofu usage and workflows
  - [Variables Guide](tofu/docs/variables-guide.md) — Configuration reference

### Architecture and Design
- **[DNS Plan](docs/dns-plan.md)** — Authoritative DNS and DHCP architecture
- **[PVE Templates](docs/pve-templates.md)** — VM template creation workflow

### Ansible Roles

Each role has comprehensive documentation in its directory:

- [openbsd_firewall](ansible/roles/openbsd_firewall/README.md) — PF, DHCP, and Unbound DNS
- [wireguard_server](ansible/roles/wireguard_server/README.md) — WireGuard VPN on OpenBSD
- [synology_nfs](ansible/roles/synology_nfs/README.md) — NFS shares on Synology NAS
- [users](ansible/roles/users/README.md) — User account management
- [system](ansible/roles/system/README.md) — Basic system configuration
- [packages](ansible/roles/packages/README.md) — Package installation
- [custom_packages](ansible/roles/custom_packages/README.md) — Custom .deb packages
- [nginx](ansible/roles/nginx/README.md) — Nginx web server
- [pve_template](ansible/roles/pve_template/README.md) — Proxmox VM templates

## Secrets and Local State
## Secrets and Local State

**Critical files (gitignored):**
- `tofu/.env` — Proxmox API credentials (required for OpenTofu)
- `ansible/keys/` — SSH private keys for authentication
- `.tfstate` files — OpenTofu state (contains infrastructure details)
- `.terraform/` — OpenTofu plugins and modules

**Best practices:**
- Never commit secrets or private keys to git
- Store credentials in a password manager
- Use different keys per environment
- Back up state files securely

See [Getting Started Guide](docs/getting-started.md) for setup details.

## Security: TruffleHog Scanning
## Security: TruffleHog Scanning

Automated secret scanning prevents accidental credential commits.

**One-off scan:**
```bash
make trufflehog           # Scan entire repository
make ansible-trufflehog   # Scan ansible/ directory
make tofu-trufflehog      # Scan tofu/ directory
```

**Pre-commit hook:**
```bash
make install-precommit-hook  # Install git hook
# Now every commit runs TruffleHog automatically
```

**Bypass temporarily:**
```bash
SKIP_TRUFFLEHOG=1 git commit -m "message"
```

The scanner uses `.trufflehog-exclude.txt` to skip known false positives and legitimate ignored paths (like `keys/`).

## Contributing

When making changes:
1. Use `--check` mode to preview changes before applying
2. Test on non-production hosts first
3. Document new roles and variables
4. Run `make trufflehog` before committing
5. Update relevant documentation

## License

This is a personal homelab configuration. Use at your own risk.

## Support

- Check [Getting Started Guide](docs/getting-started.md) for common issues
- Review role READMEs for role-specific troubleshooting
- Inspect playbook outputs with `-vvv` for detailed debugging
