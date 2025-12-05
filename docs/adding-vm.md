# Adding a new VM to the homelab

This document outlines the steps to provision and configure a new VM using OpenTofu and Ansible. The process is currently manual but follows a predictable sequence.

## Prerequisites

- Cloud image downloaded to Proxmox (`make tofu-apply` if not already done)
- VM template built (`make ansible-templates` if not already done)
- Decide on: hostname, static IP, purpose/roles

## Step 1: Define the VM in OpenTofu

Add a `proxmox_virtual_environment_vm` resource to `tofu/` (e.g., `tofu/vms.tf` or a purpose-specific file like `tofu/dns.tf`).

Example resource:

```hcl
resource "proxmox_virtual_environment_vm" "dns1" {
  name      = "dns1"
  node_name = "pve1"
  vm_id     = 101  # Choose an unused VMID

  clone {
    vm_id = 9000  # debian12-cloud template
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
        address = "10.10.15.10/24"
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

## Step 3: Add VM to Ansible inventory

Edit `ansible/inventories/hosts.yml` to add the new host:

```yaml
dns_servers:
  hosts:
    dns1:
      ansible_host: 10.10.15.10
```

If the VM needs host-specific variables, create `ansible/inventories/host_vars/dns1.yml`.

If the group is new, create `ansible/inventories/group_vars/dns_servers.yml` for shared config.

## Step 4: Verify connectivity

```bash
make ansible-ping LIMIT=dns1
```

If this fails, wait for cloud-init to complete (can take 30-60 seconds after first boot).

## Step 5: Create or assign roles

For a new VM type, you may need to create a new role under `ansible/roles/`. For common configurations, existing roles can be reused:

- `users` - Deploy user, SSH keys, sudo config
- `packages` - System packages
- `system` - Hostname, /etc/hosts, SSH settings
- `nfs_mounts` - Mount NFS shares from NAS

## Step 6: Create a playbook (if needed)

For a new host group, add a playbook in `ansible/playbooks/`:

```yaml
# ansible/playbooks/dns.yml
---
- name: Configure DNS servers
  hosts: dns_servers
  become: true
  roles:
    - users
    - packages
    - nsd  # purpose-specific role
```

## Step 7: Add Makefile target (if needed)

Add targets to `ansible/Makefile` for the new playbook:

```makefile
dns: ## Apply DNS server configuration
	$(COMPOSE) run --rm ansible ansible-playbook playbooks/dns.yml

dns-check: ## Dry-run DNS server configuration
	$(COMPOSE) run --rm ansible ansible-playbook playbooks/dns.yml --check --diff
```

## Step 8: Run the playbook

```bash
make ansible-dns-check  # Dry-run first
make ansible-dns        # Apply configuration
```

## Step 9: Update dependent systems (if needed)

Some VMs require updates to other hosts. For example, a DNS server would need:

- Firewall: Update Unbound stub-zone to point to the new DNS server
- Firewall: Update DHCP to hand out the correct domain-name

```bash
make ansible-firewall-check
make ansible-firewall
```

## Complete example: deploying dns1

```bash
# 1. Ensure base infrastructure exists
make tofu-apply           # Cloud image downloaded
make ansible-templates    # VM template built

# 2. Add dns1 resource to tofu/dns.tf (manual edit)

# 3. Provision the VM
make tofu-plan
make tofu-apply

# 4. Add dns1 to ansible inventory (manual edit)
#    - inventories/hosts.yml
#    - inventories/group_vars/dns_servers.yml
#    - inventories/host_vars/dns1.yml (if needed)

# 5. Create the nsd role and dns playbook (manual, one-time)
#    - roles/nsd/
#    - playbooks/dns.yml

# 6. Add Makefile targets (manual, one-time)
#    - dns, dns-check

# 7. Verify and configure
make ansible-ping LIMIT=dns1
make ansible-dns-check
make ansible-dns

# 8. Update firewall to use new DNS
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
