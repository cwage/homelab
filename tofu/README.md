# tofu — VM provisioning

OpenTofu (Terraform fork) configuration for provisioning VMs on Proxmox VE. All operations run via Docker — no local tofu installation needed.

## Current VMs

| Resource | VM ID | Description |
|----------|-------|-------------|
| `dns1` | 101 | NSD authoritative DNS for `lan.quietlife.net` |
| `containers` | 102 | Docker host with GTX 1050 Ti GPU passthrough |
| `openbao` | 103 | Secrets management server |

All VMs clone from a Debian stable cloud image (`images.tf`) and use cloud-init for bootstrap (SSH key, static IP, hostname).

## Setup

Tofu reads credentials from the root `.env` file (shared with Ansible). See the root [README](../README.md) getting-started section for initial `.env` setup.

```bash
make build         # build the Docker image
make init          # initialize OpenTofu (first time only)
make plan          # preview changes
make apply         # apply changes
```

## Usage

```bash
make help          # list all targets
make plan          # show what would change
make apply         # create/modify VMs
make shell         # interactive shell in the tofu container
make destroy       # destroy infrastructure (use with caution)
make trufflehog    # scan for leaked secrets
```

## Adding a VM

See [docs/adding-vm.md](../docs/adding-vm.md) for a step-by-step guide covering both the tofu and ansible sides.

## Base images

The configuration (`images.tf`) downloads the current Debian stable cloud image to Proxmox. The upstream image is qcow2; the filename uses `.img` because the Proxmox download API only accepts `.img/.iso` extensions.

## State management

State files (`terraform.tfstate`) are tracked in git. This is a single-developer workflow — pull before running `plan` or `apply` when switching machines.

## File overview

```
├── main.tf           Proxmox provider configuration
├── variables.tf      Input variables with defaults
├── images.tf         Debian cloud image download
├── dns.tf            dns1 VM
├── containers.tf     containers VM (Docker host + GPU)
├── openbao.tf        openbao VM (secrets management)
├── outputs.tf        Output values
├── Makefile          Docker-wrapped tofu commands
├── Dockerfile        OpenTofu container image
└── docker-compose.yml
```
