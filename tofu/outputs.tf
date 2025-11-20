output "debian_bookworm_cloud_image_file_id" {
  description = "Identifier for the downloaded Debian 12 cloud image on Proxmox"
  value       = proxmox_virtual_environment_download_file.debian_bookworm.id
}

output "vm_test_01_id" {
  description = "Identifier for the vm-test-01 instance"
  value       = proxmox_virtual_environment_vm.test_vm.id
}
