# homelab-tofu

OpenTofu-based infrastructure management for Proxmox homelab VMs.

## Documentation

- **[Getting Started Guide](../docs/getting-started.md)** — Complete setup instructions
- **[Variables Guide](docs/variables-guide.md)** — Configuration reference
- **[PVE Templates Workflow](../docs/pve-templates.md)** — VM template creation

## Overview

This component provisions VMs on Proxmox VE using OpenTofu (Terraform fork). All operations run via Docker for consistency and portability.

**What this manages:**
- VM provisioning on Proxmox VE
- Cloud image downloads
- VM templates (in conjunction with Ansible)
- Network and storage configuration

**What this doesn't manage:**
- VM configuration after provisioning → Use Ansible
- OS updates → Use Ansible
- Service management → Use Ansible

## Quick Reference

### Common Commands

```bash
make build      # Build OpenTofu Docker image
make init       # Initialize OpenTofu backend
make plan       # Preview infrastructure changes
make apply      # Apply changes to Proxmox
make destroy    # Destroy infrastructure (careful!)
make shell      # Interactive shell in container
make validate   # Validate configuration
make fmt        # Format .tf files
```

See `make help` for complete list.

## Prerequisites

**For detailed setup instructions, see [Getting Started Guide](../docs/getting-started.md).**

- Docker and Docker Compose
- Access to Proxmox VE host
- Proxmox API token (see Initial Setup below)

## Initial Setup

### 1. Generate Proxmox API Token

Log into your Proxmox web interface:

1. Navigate to **Datacenter → Permissions → API Tokens**
2. Click **Add** to create a new token
3. Set:
   - **User**: `root@pam` (or your preferred user)
   - **Token ID**: `tofu-token` (or any name)
   - **Privilege Separation**: Uncheck for full permissions
4. **Save the token secret** - you can't view it again

### 2. Configure Environment

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env` with your Proxmox credentials:

```bash
PM_API_URL=https://10.10.15.18:8006/api2/json
PM_API_TOKEN_ID=root@pam!tofu-token
PM_API_TOKEN_SECRET=your-secret-here
PM_NODE_NAME=pve
PM_IMAGE_DATASTORE_ID=local
PM_VM_DATASTORE_ID=local-lvm
```

**Important**: The `.env` file is gitignored and should never be committed.

See [Variables Guide](docs/variables-guide.md) for details on each variable.

### 3. Build Docker Image

```bash
make build
```

### 4. Initialize OpenTofu

```bash
make init
```

Downloads the Proxmox provider and initializes the backend.

## Usage

### Preview Changes

```bash
make plan
```

Shows what will be created, modified, or destroyed.

### Apply Changes

```bash
make apply
```

Creates or updates infrastructure. Type `yes` when prompted.

### Destroy Infrastructure

```bash
make destroy
```

**Dangerous!** Removes all managed resources. Use with extreme caution.

## What Gets Created

### On First Apply

**Cloud Images:**
- Debian 12 (Bookworm) cloud image downloaded to Proxmox
- Stored in `PM_IMAGE_DATASTORE_ID` (default: `local`)
- File: `debian-12-genericcloud-amd64.img`
- Format: qcow2 (despite `.img` extension — Proxmox API requirement)

**VM Templates (via Ansible):**

After OpenTofu downloads images, use Ansible to create templates:
```bash
cd ../ansible
make templates
```

See [PVE Templates Workflow](../docs/pve-templates.md) for the complete process.

**VMs (Optional):**

VM definitions in `main.tf` are created/managed. By default, only images are downloaded — VM creation code is commented out. Uncomment and customize as needed.

## Configuration

### Environment Variables

All configuration is in `.env` file (gitignored):

- `PM_API_URL` — Proxmox API endpoint
- `PM_API_TOKEN_ID` — API token identifier (user@realm!tokenid)
- `PM_API_TOKEN_SECRET` — API token secret
- `PM_NODE_NAME` — Proxmox node for resources (e.g., "pve")
- `PM_IMAGE_DATASTORE_ID` — Storage for cloud images
- `PM_VM_DATASTORE_ID` — Storage for VM disks

See [Variables Guide](docs/variables-guide.md) for complete reference.

### Variable Mapping

Environment variables are automatically mapped to OpenTofu variables via `docker-compose.yml`:
- `PM_API_URL` → `var.pm_api_url`
- `PM_API_TOKEN_ID` → `var.pm_api_token_id`
- etc.

## Project Structure

```
tofu/
├── Dockerfile              # OpenTofu container definition
├── docker-compose.yml      # Container orchestration
├── Makefile               # Command wrapper
├── .env                   # Configuration (gitignored!)
├── .env.example           # Configuration template
├── variables.tf           # Variable definitions
├── images.tf              # Cloud image downloads
├── main.tf                # VM definitions (optional)
├── outputs.tf             # Output values
└── docs/
    └── variables-guide.md # Configuration reference
```

## Integration with Ansible

OpenTofu and Ansible work together in a two-phase approach:

### Phase 1: OpenTofu (Infrastructure)

- Downloads cloud images to Proxmox
- (Optional) Provisions VMs from templates

### Phase 2: Ansible (Configuration)

- Creates VM templates from cloud images
- Configures running VMs (users, packages, services)

### Typical Workflow

```bash
# 1. Download cloud images
cd tofu
make apply

# 2. Create templates from images
cd ../ansible
make templates

# 3. (Optional) Provision VMs from templates
cd ../tofu
# Edit main.tf to add VM definitions
make apply

# 4. Configure VMs
cd ../ansible
# Add VMs to inventory
make ping
make users
# ... apply other roles
```

See [Getting Started Guide](../docs/getting-started.md) for detailed workflow.

## State Management

**Current**: Local state files (`.tfstate`) in working directory.

**⚠️ State files contain sensitive data:**
- Resource IDs and names
- IP addresses
- Configuration details

**Best practices:**
- ✅ Keep `.tfstate` in `.gitignore`
- ✅ Back up state files securely
- ✅ Don't share state files publicly
- ⚠️ Multi-machine workflows need coordination

**Future**: State backend migration planned (S3-compatible, HTTP backend, or Terraform Cloud).

## Security

### API Token Best Practices

- ✅ Use API tokens, not root password
- ✅ Create dedicated user for OpenTofu if possible
- ✅ Use minimum required permissions
- ✅ Rotate tokens periodically
- ❌ Never commit `.env` to git
- ❌ Never share token secrets via insecure channels

### Secret Scanning

TruffleHog automatically scans for accidentally committed secrets.

**One-off scan:**
```bash
make trufflehog
```

Uses root-level scanner that excludes known safe paths (`.terraform/`, `.env`).

**Pre-commit hook:**

Install at repository root:
```bash
cd ..
make install-precommit-hook
```

Every `git commit` then runs TruffleHog. Bypass temporarily:
```bash
SKIP_TRUFFLEHOG=1 git commit -m "message"
```

## Troubleshooting

See [Getting Started Guide](../docs/getting-started.md) for common issues.

### Quick Checks

**Docker build fails:**
```bash
make clean
make build
```

**Proxmox API connection fails:**
- Verify `.env` file exists and has correct values
- Test API manually: `curl -k https://<proxmox-ip>:8006/api2/json/version`
- Check network access to Proxmox
- Verify API token hasn't expired

**"Resource already exists":**
- Check Proxmox web UI for conflicts
- Review state file for drift: `make plan`

**State lock issues:**
- Ensure no other OpenTofu processes are running
- Check for `.terraform.tfstate.lock.info` file

## Advanced Usage

### Interactive Development

```bash
make shell
# Inside container:
tofu plan
tofu console
# etc.
```

### Format Code

```bash
make fmt
```

Formats all `.tf` files recursively.

### Validate Configuration

```bash
make validate
```

Checks configuration syntax without contacting Proxmox.

## Related Documentation

- [Getting Started Guide](../docs/getting-started.md) — Complete setup walkthrough
- [Variables Guide](docs/variables-guide.md) — Configuration reference
- [PVE Templates Workflow](../docs/pve-templates.md) — VM template creation
- [Root README](../README.md) — Repository overview
- [Ansible README](../ansible/README.md) — VM configuration management
