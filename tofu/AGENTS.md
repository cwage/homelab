# homelab-tofu Agent Guidelines

**Project**: OpenTofu-based infrastructure management for Proxmox homelab
**Purpose**: Manage VMs on Proxmox host, coordinated with ansible configuration in separate repo

## Project Overview

This repository manages VM infrastructure on a Proxmox host (10.15.15.18) using OpenTofu (Terraform fork). The actual VM configuration/provisioning is handled by the companion `homelab-ansible` repository at `/home/cwage/git/cwage/homelab-ansible`.

**Key Principles:**
- Build things piecemeal/adhoc as needed - no premature directory structure
- Keep things minimal and expandable
- All OpenTofu operations via Docker (no local tofu installation)
- Makefile-based workflow for portability

## Infrastructure Details

### Proxmox Environment
- **Host IP**: 10.15.15.18
- **API Authentication**: Token-based (permissive for full VM management)
- **Access**: Via Proxmox API through OpenTofu provider

### State Management

**Current**: Local state files (`.tfstate`) in repository
**Future**: TBD - needs decision on resilient backend
**Rationale**: Development happens across multiple machines, so local state is temporary. Need to select proper backend (S3-compatible on NAS, HTTP backend, etc.)

**TODO**: Document state backend migration path when ready

## Docker-First Workflow

**ALL OpenTofu operations MUST use Docker**

### Docker Setup
- Custom Dockerfile with OpenTofu and minimal dependencies
- `docker compose` for mounting code/configs from this repo
- Commands wrapped in Makefile targets

### Why Docker?
- Consistent tooling across machines
- No local OpenTofu installation needed
- Easy dependency management
- Portable across environments

## Development Workflow

### Makefile Targets
All infrastructure operations should be exposed as `make` targets:
- `make init` - Initialize OpenTofu backend
- `make plan` - Show planned changes
- `make apply` - Apply infrastructure changes
- `make destroy` - Destroy infrastructure (with confirmation)
- Development convenience targets as needed

### Docker Compose Structure
- Mount project directory into container
- Preserve working directory structure
- Enable interactive operations (plan/apply)
- Run in background for long-running operations with `docker compose up -d`

## OpenTofu Structure

### Module Philosophy
- **Reusable VM modules** for different VM types
- Start with minimal Debian-based VMs
- Let Ansible handle configuration (separation of concerns)
- Modules should be simple and composable

### Initial Module: `debian-vm`
- Minimal Debian installation
- Configurable: CPU, RAM, disk, network
- Cloud-init ready (for Ansible bootstrap)
- Stripped down - let config management drive the rest

### Configuration Organization
- Keep configs minimal and clear
- Use variables for environment-specific values
- Document all configuration decisions
- Avoid premature abstraction

## Proxmox API Token

### Token Permissions
- Follow Proxmox best practices for token creation
- Needs VM management capabilities:
  - VM creation/deletion
  - Storage access
  - Network configuration
  - Resource allocation
- Token will be fairly permissive (managing everything on this host)
- Store token securely (environment variables, not in code)

### Token Usage
- Pass via environment variables to Docker container
- Document in README how to generate token
- Never commit tokens to repository

## Integration with homelab-ansible

### Coordination Points
- OpenTofu creates/destroys VMs
- Ansible configures VMs after creation
- Cloud-init provides bootstrap mechanism
- Keep concerns separated (infra vs config)

### Workflow
1. OpenTofu provisions VM with cloud-init
2. Cloud-init bootstraps minimal access
3. Ansible takes over for configuration
4. Updates happen via Ansible, not OpenTofu rebuilds

## Testing Strategy

### Initial Testing
- Create simple "testing" VM first
- Validate Proxmox API connectivity
- Confirm resource allocation works
- Test destroy/recreate cycle

### Incremental Approach
- Start simple, expand as needed
- Don't build entire structure upfront
- Validate each component before adding more
- Document what works and what doesn't

## Code Style

### OpenTofu/HCL
- Use clear resource naming
- Document non-obvious choices
- Keep modules simple and readable
- Use variables with sensible defaults
- Comment complex logic

### Docker
- Minimal images when possible
- Clear, documented Dockerfiles
- Compose files should be self-explanatory
- Pin versions for reproducibility

### Makefile
- One target per logical operation
- Add help text for all targets
- Use `.PHONY` for non-file targets
- Keep target names short and memorable

## Security Considerations

- Never commit API tokens or credentials
- Use environment variables for secrets
- Document required secrets in README
- Consider secrets management strategy (sops/age) for future

## Documentation

### What to Document
- How to generate Proxmox API token
- How to build/run Docker environment
- Available Makefile targets
- State backend migration path (when ready)
- Integration points with homelab-ansible

### What Not to Document Yet
- Full directory structures (build as we go)
- Complex module patterns (keep simple)
- Advanced features (wait for need)

## Current State

**Status**: Initial setup phase
**Next Steps**:
1. Create Dockerfile with OpenTofu
2. Create docker-compose.yml for development
3. Create Makefile with basic targets
4. Set up initial OpenTofu configuration
5. Test connection to Proxmox
6. Create first minimal VM module

## Notes

- This is a living document - update as project evolves
- AGENTS.md is LAW - check frequently for compliance
- Ask for clarification on ambiguous requirements
- Build incrementally, validate frequently
