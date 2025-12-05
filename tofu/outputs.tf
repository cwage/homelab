output "debian_bookworm_cloud_image_file_id" {
  description = "Identifier for the downloaded Debian 12 cloud image on Proxmox"
  value       = proxmox_virtual_environment_download_file.debian_bookworm.id
}

output "dns1_ip" {
  description = "IP address of dns1 VM"
  value       = "10.10.15.10"
}
