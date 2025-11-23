# PVE Template Role

Creates VM templates on Proxmox VE from cloud images with cloud-init configuration for automated deployment.

## Purpose

This role automates the creation of Proxmox VM templates from cloud-init-enabled images (e.g., Debian cloud images). Templates include pre-configured users, SSH keys, and the qemu-guest-agent for improved VM management. These templates serve as the base for VM provisioning via OpenTofu or manual cloning.

## Requirements

- **Target**: Proxmox VE 7.x or 8.x host
- **Privileges**: Requires `become: true` (sudo/root access)
- **Prerequisites**:
  - Cloud images downloaded to Proxmox (via OpenTofu)
  - Deploy SSH public key available locally
  - Python 3 on Proxmox host
- **Network**: VM network bridge configured in Proxmox

## Role Variables

### Default Variables

Defined in `defaults/main.yml`:

```yaml
# Minimum VMID for templates (templates use VMID >= this value)
pve_template_min_vmid: 9000

# Storage for cloud-init snippets
pve_template_snippet_storage: local
pve_template_snippets_dir: /var/lib/vz/snippets

# Storage for cloud images
pve_template_image_dir: /var/lib/vz/template/iso

# Default cloud-init user
pve_template_default_cloud_user: deploy

# Packages to install during cloud-init
pve_template_packages:
  - qemu-guest-agent

# Wait/retry configuration
pve_template_wait_retries: 30
pve_template_wait_delay: 10

# Shutdown configuration
pve_template_shutdown_timeout: 180
pve_template_shutdown_delay: 10
pve_template_shutdown_retries: 18  # Calculated from timeout/delay

# Path to deploy SSH public key (relative to playbook directory)
pve_template_deploy_pubkey_path: "{{ playbook_dir }}/../keys/deploy.pub"

# Force recreation of templates (even if VMID exists)
pve_template_force_recreate: false
```

### Required Variables

Must be defined in inventory (`group_vars/proxmox.yml` or `host_vars/<host>.yml`):

```yaml
pve_templates:
  - name: debian12-template        # Template name (VM name)
    vmid: 9000                     # VMID (must be >= pve_template_min_vmid)
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm           # Storage for VM disk
    bridge: vmbr0                  # Network bridge
    memory: 2048                   # RAM in MB
    cores: 2                       # CPU cores
    ciuser: deploy                 # Cloud-init username
    # Optional fields:
    fqdn: template.lan.quietlife.net
    description: "Debian 12 cloud-init template"
    packages: ["qemu-guest-agent", "vim", "htop"]
    snippet_storage: local         # Override snippet storage
```

## Dependencies

- **OpenTofu images**: Cloud images must be downloaded to Proxmox first
  - See [PVE Templates documentation](../../../docs/pve-templates.md)
  - Run `make tofu-apply` to download images

## Example Usage

### Basic Playbook

Playbook is located at `playbooks/pve-templates.yml`:

```yaml
---
- name: Build Proxmox VM templates
  hosts: proxmox
  gather_facts: false
  roles:
    - pve_template
```

### Example Inventory Configuration

In `inventories/group_vars/proxmox.yml`:

```yaml
---
pve_templates:
  # Debian 12 template
  - name: debian12-template
    vmid: 9000
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 2048
    cores: 2
    ciuser: deploy
    fqdn: debian12-template.lan.quietlife.net
    description: "Debian 12 Bookworm cloud-init enabled template"

  # Minimal template for testing
  - name: debian12-minimal
    vmid: 9001
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 1024
    cores: 1
    ciuser: deploy
```

### Running the Role

```bash
# From repo root
make ansible-templates

# Or from ansible directory
make templates

# With verbose output
make templates OPTS="-vvv"
```

## What This Role Does

### 1. Validate Configuration

- Ensures `pve_templates` is defined and not empty
- Validates VMID is >= `pve_template_min_vmid` (default: 9000)
- Checks cloud image file exists on Proxmox

### 2. Load Deploy SSH Key

- Reads public key from local filesystem
- Default location: `ansible/keys/deploy.pub`
- Key will be injected into cloud-init for passwordless SSH access

### 3. Render Cloud-Init User-Data

Creates cloud-init configuration with:
- Default user (deploy)
- SSH public key authorization
- Package installation (qemu-guest-agent + any specified packages)
- Hostname and FQDN configuration
- SSH password authentication disabled
- Root SSH disabled

Example user-data:
```yaml
#cloud-config
hostname: debian12-template
fqdn: debian12-template.lan.quietlife.net
manage_etc_hosts: true
users:
  - name: deploy
    groups: [sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA...
packages:
  - qemu-guest-agent
  - vim
package_update: true
package_upgrade: true
ssh_pwauth: false
disable_root: true
```

### 4. Create/Replace VM

**If VMID exists:**
- If it's already a template: Destroy and recreate
- If it's a VM and `pve_template_force_recreate=true`: Destroy and recreate
- Otherwise: Skip (fail-safe)

**VM creation:**
- Uses `qm create` command with specified resources
- Imports cloud image disk
- Configures cloud-init drive
- Attaches network interface

### 5. Boot VM and Wait

- Starts the VM
- Waits for qemu-guest-agent to become available
- Polls with configurable retries (default: 30 × 10s = 5 minutes)
- Verifies agent is reporting IP address

### 6. Shutdown VM

- Issues graceful shutdown via guest agent
- Waits for VM to stop (with timeout)
- Retries if VM doesn't stop in time

### 7. Convert to Template

- Runs `qm template <vmid>` to mark VM as template
- Template becomes read-only and cannot be started
- Can only be cloned to create new VMs

## Outputs

After running this role:
- VM templates exist in Proxmox with configured VMIDs
- Templates include cloud-init configuration
- Deploy user is pre-configured with SSH key
- qemu-guest-agent is installed and enabled
- Templates are ready for cloning via OpenTofu or Proxmox UI

## Workflow Integration

This role fits into the larger infrastructure workflow:

```
1. OpenTofu downloads cloud images → Proxmox datastore
2. Ansible creates templates from images
3. OpenTofu clones templates to create VMs
4. Cloud-init runs on first boot (from template)
5. Ansible configures VMs (post-deployment)
```

See [PVE Templates documentation](../../../docs/pve-templates.md) for complete workflow.

## Assumptions and Limitations

### Assumptions
- Cloud images are qcow2 format
- Images support cloud-init
- Proxmox has sufficient storage for template disks
- Deploy SSH key is already generated
- Network bridge exists in Proxmox

### Limitations
- Only supports single-disk templates
- Single network interface only
- No custom partitioning
- Cloud-init config is fairly basic
- No multi-architecture support (amd64 only)

### Safety Features
- Won't destroy non-template VMs unless `pve_template_force_recreate=true`
- Validates VMID minimum to avoid ID conflicts
- Checks image exists before attempting import
- Graceful shutdown with timeout
- Idempotent: can be run multiple times safely

## Template Configuration Options

### Minimal Template

```yaml
pve_templates:
  - name: minimal-template
    vmid: 9010
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 512
    cores: 1
    ciuser: deploy
```

### Production Template

```yaml
pve_templates:
  - name: prod-template
    vmid: 9020
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 4096
    cores: 4
    ciuser: deploy
    fqdn: prod-template.lan.quietlife.net
    description: "Production Debian 12 template - full featured"
    packages:
      - qemu-guest-agent
      - vim
      - htop
      - curl
      - git
```

### Custom User Template

```yaml
pve_templates:
  - name: custom-template
    vmid: 9030
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 2048
    cores: 2
    ciuser: admin  # Different username
    snippet_storage: local  # Override snippet storage
```

## Common Issues

**"Image file not found":**
- Run OpenTofu first: `make tofu-apply`
- Check image exists: `ls /var/lib/vz/template/iso/`
- Verify filename matches exactly (case-sensitive)
- Ensure image was downloaded successfully by OpenTofu

**"VMID already exists":**
- Check if VM/template exists: `qm list | grep <vmid>`
- If it's a template you want to replace: It will be destroyed and recreated
- If it's a VM: Set `pve_template_force_recreate=true` or use different VMID
- Never use VMIDs < 9000 (reserved for templates)

**"Timeout waiting for guest agent":**
- Image may not support qemu-guest-agent
- VM may not have booted successfully
- Check VM console: Proxmox UI → VM → Console
- Increase `pve_template_wait_retries` or `pve_template_wait_delay`
- Check VM logs: `journalctl -u qemu-guest-agent`

**"VM won't shutdown":**
- Guest agent may not be running
- Increase `pve_template_shutdown_timeout`
- Check VM console for errors
- May need to force stop (manual intervention)

**"Permission denied" during image import:**
- Check Proxmox storage permissions
- Verify datastore supports disk images
- Check disk space: `df -h /var/lib/vz/`

**SSH key not working in cloned VMs:**
- Verify public key file exists and is readable
- Check cloud-init logs in cloned VM: `/var/log/cloud-init.log`
- Ensure private key matches public key
- Verify key path is correct in defaults

## Testing

```bash
# Build templates
make ansible-templates

# Check template exists in Proxmox
ansible proxmox -m shell -a "qm list | grep 9000" --become

# Check cloud-init snippet
ansible proxmox -m shell -a "cat /var/lib/vz/snippets/9000-user-data.yml" --become

# Test cloning (via Proxmox UI or qm command)
ansible proxmox -m shell -a "qm clone 9000 100 --name test-vm" --become

# Start cloned VM and check cloud-init
ansible proxmox -m shell -a "qm start 100" --become
# Wait for boot, then SSH to test-vm
ssh deploy@<test-vm-ip>
```

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial setup
- [PVE Templates Workflow](../../../docs/pve-templates.md) — Complete template workflow
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/) — Cloud-init reference
- [Proxmox Cloud-Init](https://pve.proxmox.com/wiki/Cloud-Init_Support) — Proxmox specifics
- [OpenTofu Images](../../../tofu/images.tf) — Image download configuration
