variable "pm_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "pm_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "pm_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "pm_node_name" {
  description = "Proxmox node where images and VMs will be managed"
  type        = string
}

variable "pm_image_datastore_id" {
  description = "Datastore ID for downloaded cloud images (typically a dir/iso-capable store like 'local')"
  type        = string
  default     = "local"
}

variable "pm_vm_datastore_id" {
  description = "Datastore ID for VM disks/cloud-init volumes (typically 'local-lvm')"
  type        = string
  default     = "local-lvm"
}

variable "pm_lan_bridge" {
  description = "Bridge to attach VM NICs to the LAN"
  type        = string
  default     = "vmbr0"
}

variable "pm_debian12_template_id" {
  description = "Template VMID for Debian 12 cloud-init base"
  type        = number
  default     = 9000
}
