output "debian_bookworm_cloud_image_file_id" {
  description = "Identifier for the downloaded Debian 12 cloud image on Proxmox"
  value       = proxmox_virtual_environment_download_file.debian_bookworm.id
}

# Hardcoded rather than derived from resource attributes because the
# Proxmox provider doesn't cleanly expose cloud-init IPs as outputs.
output "dns1_ip" {
  description = "IP address of dns1 VM"
  value       = "10.10.15.10"
}

output "containers_ip" {
  description = "IP address of containers VM"
  value       = "10.10.15.12"
}
