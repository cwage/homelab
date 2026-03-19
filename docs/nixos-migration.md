# NixOS VM migration

Tracked by [#132](https://github.com/cwage/homelab/issues/132). Proxmox VMs are migrating from Debian + Ansible to NixOS, managed declaratively from `flake.nix`. Ansible stays for non-NixOS hosts (OpenBSD firewall, Linode VPSes, Synology NAS).

## How it works

### Build and deploy pipeline

1. **Template**: `make nix-template` builds a base NixOS Proxmox VMA image (Dockerized, no host Nix install). `make nix-deploy` uploads it as VMID 9001.
2. **Provision**: OpenTofu clones from template 9001 to create a VM (cloud-init sets IP, hostname, SSH key).
3. **Deploy**: `make nix-deploy-host HOST=<name> TARGET=<ip>` builds the host-specific NixOS config in Docker, copies store paths to the target via `nix copy`, and activates remotely over SSH.

The target VM must have `nix.settings.trusted-users = [ "root" "deploy" ]` (baked into the template via `modules/base.nix`) so the builder can push unsigned store paths.

### Secrets via OpenBao AppRole

NixOS hosts fetch secrets from OpenBao at runtime using the `openbao-agent` NixOS module (`modules/openbao-agent.nix`). No secrets are stored in git or baked into images.

**How AppRole auth works:**

- Each NixOS host gets an AppRole role CIDR-bound to its static IP (no secret_id needed on a trusted LAN).
- The `role_id` is written to `/etc/openbao/role_id` by the NixOS config (not secret — only the bound IP can use it).
- `openbao-agent` runs as a systemd service, authenticates via AppRole, and templates secrets to file paths.
- Services reference these files (e.g., `hashedPasswordFile = "/etc/secrets/cwage-password-hash"`).

**To add a new NixOS host with secrets:**

```bash
# 1. Create a CIDR-bound AppRole for the host
make openbao-approle-create-role NAME=myhost IP=10.10.15.XX

# 2. Get the role_id
make openbao-approle-show-role NAME=myhost

# 3. Create hosts/myhost/configuration.nix with the role_id and secrets map
# 4. Add nixosConfigurations.myhost to flake.nix
# 5. Deploy
make nix-deploy-host HOST=myhost TARGET=10.10.15.XX
```

### Migrating an existing Debian/Ansible VM

The general pattern (per-host details will vary):

1. Write `hosts/<name>/configuration.nix` translating the Ansible role config to NixOS modules.
2. Add the `nixosConfigurations.<name>` entry to `flake.nix`.
3. Create an AppRole if the host needs secrets (`make openbao-approle-create-role`).
4. Update `tofu/<name>.tf` to clone from the NixOS template (9001) instead of the Debian template.
5. Tear down the old VM and apply Tofu to create the new one.
6. Deploy the NixOS config: `make nix-deploy-host HOST=<name> TARGET=<ip>`.
7. Verify services, then remove the corresponding Ansible role when confident.

DNS (dns1) is the first migration target — simplest VM, lowest risk.

## File layout

```
flake.nix                        # NixOS host definitions
modules/
  base.nix                       # Shared: deploy user, cwage user, SSH, packages, trusted-users
  openbao-agent.nix              # OpenBao agent systemd service with AppRole auto-auth
hosts/
  <hostname>/configuration.nix   # Per-host NixOS config
nix/
  deploy.sh                      # Build locally, nix copy to target, activate over SSH
  Makefile                       # make targets: template, deploy, deploy-host
  docker-compose.yml             # Dockerized Nix builder
openbao/
  Makefile                       # AppRole management targets
  docker-compose.yml             # Dockerized OpenBao CLI
  scripts/setup-approle.sh       # AppRole setup script
```

## Known issues

- **NixOS template uses virtio0, not scsi0**: Tofu VM definitions for NixOS hosts must NOT include a `disk` block (inherits the template's virtio0). Use `boot_order = ["virtio0"]`.
- **Proxmox lock files after interrupted Tofu**: If `tofu apply` is interrupted (ctrl+c), a stale lock file at `/var/lock/qemu-server/lock-<vmid>.conf` may persist. Fix: `ssh deploy@pve1 "sudo rm /var/lock/qemu-server/lock-<vmid>.conf"`.
