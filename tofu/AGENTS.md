# OpenTofu Agent Guidelines

## Overview

OpenTofu configuration for provisioning VMs on a Proxmox VE host (pve1, 10.10.15.18). VM configuration after provisioning is handled by Ansible (see `../ansible/`).

## Key Principles

- All OpenTofu operations run via Docker (`make` targets) — never run `tofu` directly on the host
- Flat file structure — no modules directory; each VM gets its own `.tf` file
- Let Ansible handle post-provisioning configuration (separation of concerns)
- State tracked in git (single-developer workflow)

## Structure

- `main.tf` — Provider config (bpg/proxmoxve)
- `variables.tf` — All input variables with descriptions and defaults
- `images.tf` — Debian cloud image download for Proxmox
- Individual VM files: `dns.tf`, `containers.tf`, `openbao.tf`
- `outputs.tf` — Output values

## Credentials

All credentials come from the root `.env` file via `--env-file ../.env`:
- `PM_API_URL`, `PM_API_TOKEN_ID`, `PM_API_TOKEN_SECRET` — Proxmox API access
- `BAO_ADDR`, `BAO_TOKEN` — OpenBao (shared with Ansible)

## Conventions

- All VMs use the same Debian cloud image (cloned from template)
- Cloud-init handles: deploy user, SSH key, static IP, DNS settings
- Hostnames are managed by Ansible (hostname role), not cloud-init
- VMs attach to `vmbr0` bridge unless explicitly specified otherwise
- Static IPs in the 10.10.15.10-99 range for infrastructure VMs

## Adding a VM

See `../docs/adding-vm.md` for the full workflow.

## Security

- Never commit `.env` files or API tokens
- State files may contain sensitive values — review before sharing the repo
- Use OpenBao for secrets rather than hardcoding values
