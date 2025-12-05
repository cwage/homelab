# homelab-tofu

OpenTofu-based infrastructure management for Proxmox homelab VMs.

## Overview

This repository manages VM infrastructure on Proxmox using OpenTofu (Terraform fork). All operations run via Docker for consistency and portability across development machines.

**Companion Repository**: [homelab-ansible](https://github.com/cwage/homelab-ansible) handles VM configuration after provisioning.

## Prerequisites

- Docker and Docker Compose
- Access to Proxmox host at 10.15.15.18
- Proxmox API token (see below)

## Initial Setup

### 1. Generate Proxmox API Token

Log into your Proxmox web interface and create an API token:

1. Navigate to **Datacenter → Permissions → API Tokens**
2. Click **Add** to create a new token
3. User: `root@pam` (or your preferred user)
4. Token ID: `tofu-token` (or your preferred name)
5. **Uncheck** "Privilege Separation" for full permissions (or set specific privileges as needed)
6. Save the token secret - you won't be able to view it again

### 2. Configure Environment

Copy the example environment file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env` with your Proxmox credentials:

```bash
PM_API_URL=https://10.15.15.18:8006/api2/json
PM_API_TOKEN_ID=root@pam!tofu-token
PM_API_TOKEN_SECRET=your-secret-here
PM_NODE_NAME=pve                     # Proxmox node to manage images/VMs
PM_IMAGE_DATASTORE_ID=local          # Datastore for downloaded cloud images
```

**Important**: The `.env` file is gitignored and should never be committed.

### 3. Build Docker Image

```bash
make build
```

## Usage

All OpenTofu operations use the Makefile:

```bash
make help       # Show available commands
make init       # Initialize OpenTofu (run once)
make plan       # Preview infrastructure changes
make apply      # Apply changes
make destroy    # Destroy infrastructure
make shell      # Open interactive shell in container
```

### Common Workflows

**First time setup:**
```bash
make build
make init
```

**Make infrastructure changes:**
```bash
make plan      # Review changes
make apply     # Apply if everything looks good
```

**Interactive development:**
```bash
make shell     # Opens bash in container with tofu available
```

## Base images (Debian bookworm)

The configuration downloads the current Debian stable cloud image to the `PM_IMAGE_DATASTORE_ID` datastore on `PM_NODE_NAME`. Run `make plan`/`make apply` to pull or refresh the file (`debian-12-genericcloud-amd64.img` stored under `template/iso`). The upstream image is qcow2; the filename uses `.img` because the Proxmox download API only accepts `.img/.iso` extensions, but the content remains qcow2. Future VM/template resources can reference this downloaded image ID directly.

## Secret scanning and pre-commit hook

TruffleHog runs inside Docker (service `trufflehog` in `docker-compose.yml`) so everyone uses the same scanner version without installing anything locally.

### One-off scans

```
make trufflehog
```

The target wraps `docker compose run --rm trufflehog filesystem /workspace --fail --no-update` and automatically loads `.trufflehog-exclude.txt` to ignore local-only artifacts like `.terraform/` or `.env`. Override the command with `TRUFFLEHOG_ARGS` when you need extra flags:

```
make trufflehog TRUFFLEHOG_ARGS="filesystem /workspace --fail --only-verified"
```

### Installing the git pre-commit hook

Install the repo-managed hook into `.git/hooks/pre-commit` to block accidental secret commits:

```
./scripts/install-precommit-hook.sh
```

Every `git commit` then runs the same Dockerized scan. Set `SKIP_TRUFFLEHOG=1` to bypass temporarily or pass hook-specific options with `TRUFFLEHOG_PRECOMMIT_ARGS="..."` (document why if used). Mirror `make trufflehog` in CI to ensure pushes/PRs fail if the scan finds a problem.

## Project Structure

```
.
├── Dockerfile           # OpenTofu Docker environment
├── docker-compose.yml   # Container orchestration
├── Makefile            # Command shortcuts
├── .env.example        # Environment template
└── AGENTS.md           # Development guidelines
```

## State Management

State files (`terraform.tfstate`) are tracked in git for simplicity. This is a single-developer workflow, so the locking concerns with remote backends don't apply.

**Workflow notes:**
- After running `make apply`, commit and push the updated state files
- When switching machines, pull before running `plan` or `apply`

## Security Notes

- Never commit `.env` files or API tokens
- State files may contain sensitive data - review before sharing
- API tokens should have minimum required permissions
- Consider using `sops` or similar for secrets management (future)

## Integration with Ansible

1. OpenTofu provisions VMs with cloud-init
2. Cloud-init bootstraps SSH access
3. Ansible (from homelab-ansible repo) handles configuration
4. Updates happen via Ansible, not OpenTofu rebuilds

## Troubleshooting

**Docker build fails:**
- Check internet connectivity
- Verify OpenTofu version in Dockerfile is available
- Try `make clean` then `make build`

**Proxmox API connection fails:**
- Verify `.env` file exists and has correct values
- Check Proxmox API token is valid and not expired
- Confirm network access to 10.15.15.18:8006
- Check SSL certificate issues (may need to configure TLS verification)

**State lock issues:**
- If using local state, ensure no other processes are running
- Check for `.terraform.tfstate.lock.info` files

## Development Guidelines

See [AGENTS.md](./AGENTS.md) for comprehensive development guidelines and project conventions.
