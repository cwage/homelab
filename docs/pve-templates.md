# Proxmox VM templates

This repo maintains two VM templates on Proxmox. New VMs clone from one of these templates and get their identity (IP, hostname, SSH key) via cloud-init at first boot.

| Template | VMID | OS | Built by | Build command |
|----------|------|----|----------|---------------|
| `debian12-cloud` | 9000 | Debian 12 | Ansible (`pve_template` role) | `make ansible-templates` |
| `nixos-template` | 9001 | NixOS | Nix (Dockerized flake build) | `make nix-template` + `make nix-deploy` |

**Direction:** New VMs should use the NixOS template (9001) unless there's a specific reason to use Debian. Existing Debian VMs will migrate to NixOS over time — see [docs/nixos-migration.md](nixos-migration.md) for the migration playbook.

## NixOS template (VMID 9001) — preferred

The NixOS template is built from `flake.nix` → `nix/template.nix` using a Dockerized Nix builder (no host Nix install required). It produces a Proxmox VMA image that gets uploaded and converted to a template.

### What's baked in

- Cloud-init support (IP, hostname, SSH key set at clone time)
- `deploy` user with SSH key and passwordless sudo
- `qemu-guest-agent` enabled
- `nix.settings.trusted-users` includes `deploy` (required for remote `nix copy` deploys)
- virtio disk on `virtio0` (not scsi0 — this matters for Tofu definitions)

### Building and deploying

```bash
make nix-template   # Build VMA image to nix/output/
make nix-deploy     # Upload to Proxmox, restore as VMID 9001, convert to template
```

Rebuild the template whenever `nix/template.nix`, `modules/base.nix`, or `flake.nix` changes.

### Tofu considerations for NixOS VMs

NixOS VMs inherit a `virtio0` disk from the template. In the Tofu resource definition:

- Use `interface = "virtio0"` in the `disk` block (not `scsi0`)
- Set `boot_order = ["virtio0"]`

See `tofu/dns1.tf` for a working example.

### Configuration files

```
flake.nix              # nixosConfigurations.proxmox-template entry
nix/template.nix       # Proxmox VMA image settings (cores, memory, network)
modules/base.nix       # Shared base config baked into the template
nix/Makefile           # Build target + template deploy target (upload, restore, convert-to-template)
nix/build.sh           # Build script (runs inside Docker)
nix/deploy.sh          # Host configuration deploy script (used by `make nix-deploy-host`)
```

## Debian template (VMID 9000) — legacy

The Debian template is built by the Ansible `pve_template` role. It downloads a cloud image via OpenTofu, then uses Ansible to create a VM from that image, run cloud-init, and convert it to a template.

### What's baked in

- Cloud-init support (IP, hostname, SSH key set at clone time)
- `deploy` user with SSH key
- `qemu-guest-agent` installed and enabled
- scsi disk on `scsi0`

### Building and deploying

```bash
# 1. Ensure the base image is downloaded
make tofu-plan    # Should show the Debian cloud image in tofu/images.tf
make tofu-apply

# 2. Build the template
make ansible-templates
```

### Configuration files

```
tofu/images.tf                                    # Upstream cloud image download
ansible/inventories/group_vars/proxmox.yml        # Template definition (name, VMID, image, specs)
ansible/roles/pve_template/                       # Role that builds the template
ansible/playbooks/pve-templates.yml               # Playbook entry point
```

### Adding a new Debian template

1. Add the base image to `tofu/images.tf` and apply.
2. Add an entry to `pve_templates` in `ansible/inventories/group_vars/proxmox.yml`:
   - `name`, `vmid` (>= 9000, unique), `image_file` (must match the tofu download filename)
   - `datastore`, `bridge`, `memory`, `cores`, `ciuser` (default `deploy`)
3. Run `make ansible-templates`.

## Which template to use

| Scenario | Template |
|----------|----------|
| New infrastructure VM | NixOS (9001) |
| Migrating an existing Debian VM | NixOS (9001) — see [nixos-migration.md](nixos-migration.md) |
| VM that requires Debian-specific packages or workflows | Debian (9000) |

After cloning from either template, see [docs/adding-vm.md](adding-vm.md) for the full VM provisioning walkthrough.
