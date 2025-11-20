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
