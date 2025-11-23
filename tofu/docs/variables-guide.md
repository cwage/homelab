# OpenTofu Variables and Configuration

This guide explains the variables and configuration options available in the OpenTofu infrastructure code.

## Overview

OpenTofu (Terraform fork) provisions VMs and manages images on Proxmox VE. All configuration is done through variables defined in `.env` files, which are passed to OpenTofu as `TF_VAR_` environment variables.

## Environment File Structure

The `.env` file contains all required configuration. It is **gitignored** and must never be committed.

### Complete .env File

Based on `.env.example`:

```bash
# Proxmox API Configuration
# Copy this file to .env and fill in your actual values
# The .env file is gitignored for security

# Proxmox API URL (https://your-proxmox-host:8006/api2/json)
PM_API_URL=https://10.10.15.18:8006/api2/json

# Proxmox API Token ID (format: user@realm!tokenid)
# Example: root@pam!tofu-token
PM_API_TOKEN_ID=root@pam!tofu-token

# Proxmox API Token Secret
PM_API_TOKEN_SECRET=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Proxmox node where images/VMs are managed (e.g., pve)
PM_NODE_NAME=pve

# Datastore for downloaded cloud images (dir/iso-capable; defaults to 'local')
PM_IMAGE_DATASTORE_ID=local

# Datastore for VM disks/cloud-init media (defaults to 'local-lvm')
PM_VM_DATASTORE_ID=local-lvm
```

## Variable Mapping

Environment variables are prefixed with `TF_VAR_` to map to OpenTofu variables. The `docker-compose.yml` handles this automatically:

```yaml
environment:
  - TF_VAR_pm_api_url=${PM_API_URL}
  - TF_VAR_pm_api_token_id=${PM_API_TOKEN_ID}
  - TF_VAR_pm_api_token_secret=${PM_API_TOKEN_SECRET}
  - TF_VAR_pm_node_name=${PM_NODE_NAME}
  - TF_VAR_pm_image_datastore_id=${PM_IMAGE_DATASTORE_ID}
  - TF_VAR_pm_vm_datastore_id=${PM_VM_DATASTORE_ID}
```

## Variable Definitions

All variables are defined in `variables.tf`:

### API Authentication

```hcl
variable "pm_api_url" {
  description = "Proxmox API URL (https://host:8006/api2/json)"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API token ID (user@realm!tokenid)"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}
```

**Usage:**
- Generate token in Proxmox UI: Datacenter → Permissions → API Tokens
- Format: `username@realm!tokenid` (e.g., `root@pam!tofu-token`)
- Secret is shown once during creation — save it immediately

### Node and Storage

```hcl
variable "pm_node_name" {
  description = "Proxmox node name for provisioning"
  type        = string
  default     = "pve"
}

variable "pm_image_datastore_id" {
  description = "Datastore for cloud images (must support ISO/directory)"
  type        = string
  default     = "local"
}

variable "pm_vm_datastore_id" {
  description = "Datastore for VM disks"
  type        = string
  default     = "local-lvm"
}
```

**Storage Types:**
- `local`: Directory storage, supports ISOs and snippets
- `local-lvm`: LVM storage, for VM disks (thin provisioned)
- Custom: Any storage you've configured in Proxmox

### Network

```hcl
variable "pm_lan_bridge" {
  description = "Network bridge for LAN connectivity"
  type        = string
  default     = "vmbr0"
}
```

**Bridge Configuration:**
- Bridges are defined in Proxmox: Node → System → Network
- `vmbr0` is the default bridge created during Proxmox installation
- Multiple bridges can exist for network segmentation

### Template IDs

```hcl
variable "pm_debian12_template_id" {
  description = "VMID of Debian 12 template (created by Ansible pve_template role)"
  type        = number
  default     = 9000
}
```

**Template Management:**
- Templates are created by Ansible (see pve_template role)
- VMID must match the template created by Ansible
- Default: 9000 for Debian 12 template

## Resource Configuration

### Cloud Images

Defined in `images.tf`:

```hcl
resource "proxmox_virtual_environment_download_file" "debian12_image" {
  node_name    = var.pm_node_name
  content_type = "iso"
  datastore_id = var.pm_image_datastore_id

  file_name = "debian-12-genericcloud-amd64.img"
  url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
  
  overwrite           = false
  overwrite_unmanaged = false
}
```

**Key Points:**
- `content_type = "iso"`: Proxmox API requires this even for qcow2 images
- `file_name`: Must end in `.img` or `.iso` (API restriction)
- `url`: Upstream cloud image location
- `overwrite = false`: Won't re-download if file exists

### VM Definitions

Example VM in `main.tf` (commented out by default):

```hcl
# Example VM definition (commented out - customize as needed)
# resource "proxmox_virtual_environment_vm" "example" {
#   name        = "example-vm"
#   description = "Example VM from template"
#   node_name   = var.pm_node_name
#   vm_id       = 100
#   
#   clone {
#     vm_id = var.pm_debian12_template_id
#     full  = true
#   }
#   
#   cpu {
#     cores = 2
#     type  = "host"
#   }
#   
#   memory {
#     dedicated = 2048
#   }
#   
#   network_device {
#     bridge = var.pm_lan_bridge
#   }
#   
#   disk {
#     datastore_id = var.pm_vm_datastore_id
#     interface    = "scsi0"
#     size         = 20
#   }
# }
```

## Common Configurations

### Single Node Setup

```bash
# .env
PM_API_URL=https://10.10.15.18:8006/api2/json
PM_API_TOKEN_ID=root@pam!tofu-token
PM_API_TOKEN_SECRET=your-secret
PM_NODE_NAME=pve
PM_IMAGE_DATASTORE_ID=local
PM_VM_DATASTORE_ID=local-lvm
```

### Multiple Datastores

```bash
# .env with custom storage
PM_IMAGE_DATASTORE_ID=nfs-templates  # NFS storage for images
PM_VM_DATASTORE_ID=ssd-pool          # SSD storage pool for VMs
```

### Custom Network

```bash
# .env with VLAN bridge
PM_LAN_BRIDGE=vmbr1  # If using secondary bridge
```

## Security Considerations

### API Token Permissions

**Minimal permissions for OpenTofu:**
- VM.Allocate
- VM.Config.*
- VM.Monitor
- Datastore.AllocateSpace
- Datastore.Audit

**Production recommendations:**
- Create dedicated user for OpenTofu
- Use API tokens, not password authentication
- Enable "Privilege Separation" if possible
- Audit token usage regularly

### Environment File Security

**Best practices:**
- ✅ Never commit `.env` to git (in `.gitignore`)
- ✅ Store secrets in password manager
- ✅ Use different tokens per environment
- ✅ Rotate tokens periodically
- ❌ Don't share `.env` via insecure channels
- ❌ Don't use root password instead of tokens

### State File Security

**Local state risks:**
- State files may contain sensitive data (IPs, IDs)
- `.tfstate` is gitignored but exists locally
- Consider remote backend for production

**Future enhancement:**
- Migrate to S3-compatible backend (MinIO on NAS)
- Enable state locking
- Encrypt state at rest

## Variable Validation

OpenTofu validates variables automatically:

```hcl
variable "pm_api_url" {
  type = string
  validation {
    condition     = can(regex("^https://", var.pm_api_url))
    error_message = "API URL must start with https://"
  }
}
```

## Debugging Configuration

### View Current Variables

```bash
# In container
make shell
tofu console

# Then type:
var.pm_node_name
var.pm_image_datastore_id
```

### Validate Configuration

```bash
make validate
```

### Check for Drift

```bash
make plan
```

Shows differences between state and actual infrastructure.

## Common Issues

**"Error: missing required variable":**
- Ensure `.env` file exists
- Check all required variables are defined
- Verify `docker-compose.yml` maps all variables

**"Error: 401 Unauthorized":**
- Check `PM_API_TOKEN_ID` format (user@realm!tokenid)
- Verify token secret is correct
- Ensure token hasn't expired
- Check token permissions in Proxmox UI

**"Error: node not found":**
- Verify `PM_NODE_NAME` matches node in Proxmox cluster
- Check node name in Proxmox UI (Datacenter → Nodes)
- Node names are case-sensitive

**"Error: datastore not found":**
- Check storage exists: Datacenter → Storage
- Verify storage name matches exactly
- Ensure storage is enabled on target node

**"Error: bridge not found":**
- Check network config: Node → System → Network
- Verify bridge name (usually `vmbr0`)
- Ensure bridge is active

## Advanced Usage

### Multiple VMs from Template

```hcl
variable "vm_count" {
  default = 3
}

resource "proxmox_virtual_environment_vm" "cluster" {
  count     = var.vm_count
  name      = "node-${count.index + 1}"
  node_name = var.pm_node_name
  vm_id     = 100 + count.index
  
  clone {
    vm_id = var.pm_debian12_template_id
  }
  
  # ... rest of config
}
```

### Environment-Specific Variables

```hcl
variable "environment" {
  default = "dev"
}

locals {
  vm_sizes = {
    dev  = { cores = 1, memory = 1024 }
    prod = { cores = 4, memory = 8192 }
  }
  
  size = local.vm_sizes[var.environment]
}
```

### Conditional Resources

```hcl
variable "enable_monitoring_vm" {
  type    = bool
  default = false
}

resource "proxmox_virtual_environment_vm" "monitoring" {
  count = var.enable_monitoring_vm ? 1 : 0
  
  # ... config
}
```

## Related Documentation

- [Getting Started Guide](../../docs/getting-started.md) — Initial setup
- [OpenTofu README](../README.md) — Usage and workflows
- [Variables.tf](../variables.tf) — Complete variable definitions
- [Proxmox Provider Docs](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
