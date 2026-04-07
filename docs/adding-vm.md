# Adding a new VM to the homelab

This document outlines the steps to provision and configure a new VM using OpenTofu and Ansible. The process is currently manual but follows a predictable sequence.

## Prerequisites

- A VM template on Proxmox — see [docs/pve-templates.md](pve-templates.md) for both options:
  - **NixOS (VMID 9001, preferred)**: `make nix-template` + `make nix-deploy`
  - **Debian (VMID 9000)**: `make tofu-apply` (downloads cloud image) + `make ansible-templates`
- Decide on: hostname, static IP, purpose/roles

## Step 1: Define the VM in OpenTofu

Add a `proxmox_virtual_environment_vm` resource to `tofu/` (e.g., `tofu/vms.tf` or a purpose-specific file like `tofu/dns.tf`).

Example resource (Debian — for NixOS, see the [dns1 example](#complete-example-deploying-dns1-nixos) below or `tofu/dns1.tf`):

```hcl
resource "proxmox_virtual_environment_vm" "myhost" {
  name      = "myhost"
  node_name = "pve1"
  vm_id     = 101  # Choose an unused VMID

  clone {
    vm_id = var.pm_template_id  # 9000 (Debian) or var.pm_nixos_template_id (9001, NixOS)
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    hostname = "dns1"

    ip_config {
      ipv4 {
        address = "10.10.15.15/24"
        gateway = "10.10.15.1"
      }
    }

    user_account {
      username = "deploy"
      keys     = [file("~/.ssh/deploy.pub")]
    }
  }

  lifecycle {
    ignore_changes = [initialization]
  }
}
```

Optionally add an output in `tofu/outputs.tf`:

```hcl
output "dns1_ip" {
  value = proxmox_virtual_environment_vm.dns1.ipv4_addresses[0][0]
}
```

## Step 2: Provision the VM

```bash
make tofu-plan    # Review changes
make tofu-apply   # Create the VM
```

The VM will boot, run cloud-init, and be reachable via SSH as the `deploy` user.

## Step 3: Configure the VM

There are two paths depending on whether the VM runs NixOS or Debian:

### NixOS path (preferred for new VMs)

1. Create `hosts/<hostname>/configuration.nix` with the host config
2. Add a `nixosConfigurations.<hostname>` entry in `flake.nix`
3. `git add` the new files (Nix flakes require tracked files)
4. Deploy: `make nix-deploy-host HOST=<hostname> TARGET=<ip>`

For secrets delivery, create an AppRole: `make openbao-approle-create-role NAME=<hostname> IP=<ip>`, then set `roleId` in the host config and enable `homelab.openbao-agent`.

### Ansible path (for non-NixOS hosts)

1. Add host to `ansible/inventories/hosts.yml`
2. Create roles and a playbook under `ansible/playbooks/`
3. Add Makefile targets in `ansible/Makefile`
4. Run: `make ansible-<target>`

## Step 4: Verify connectivity

```bash
# NixOS hosts
ssh deploy@<ip> hostname

# Ansible-managed hosts
make ansible-ping LIMIT=<hostname>
```

If this fails, wait for cloud-init to complete (can take 30-60 seconds after first boot).

## Step 5: Update dependent systems (if needed)

Some VMs require updates to other hosts. For example, a DNS server would need:

- Firewall: Update Unbound stub-zone to point to the new DNS server
- Firewall: Update DHCP to hand out the correct domain-name

```bash
make ansible-firewall-check
make ansible-firewall
```

## Complete example: deploying dns1 (NixOS)

```bash
# 1. Ensure NixOS template exists on Proxmox
make nix-template         # Build VMA image
make nix-deploy           # Upload to Proxmox as template 9001

# 2. Add dns1 resource to tofu/dns1.tf (manual edit, clone from NixOS template)

# 3. Provision the VM
make tofu-plan
make tofu-apply

# 4. Create NixOS host config
#    - hosts/dns1/configuration.nix (NSD zones, services, etc.)
#    - Add nixosConfigurations.dns1 to flake.nix
#    - git add the new files

# 5. Deploy NixOS config
make nix-deploy-host HOST=dns1 TARGET=10.10.15.15

# 6. Set up secrets delivery (optional)
make openbao-approle-create-role NAME=dns1 IP=10.10.15.15
#    Update roleId in configuration.nix, redeploy

# 7. Add DNS record for the new host (edit hosts/dns1/configuration.nix zone data)
make nix-deploy-host HOST=dns1 TARGET=10.10.15.15

# 8. Update firewall if needed (e.g., Unbound stub-zones, DHCP)
make ansible-firewall-check
make ansible-firewall
```

## Notes

- **Static IPs**: Use static IPs for infrastructure VMs to avoid chicken-and-egg issues with DNS/DHCP.
- **VMID allocation**: Keep track of used VMIDs. Templates use 9000+, VMs can use lower numbers.
- **cloud-init timing**: The VM may take 30-60 seconds after boot before SSH is available.
- **Idempotency**: All Ansible playbooks should be idempotent—safe to re-run.

## Future improvements

- Wrapper make target to orchestrate tofu + ansible in sequence
- Dynamic inventory from Tofu state or Proxmox API
- Shared host data model for DNS/DHCP parity (see `docs/dns-plan.md`)
