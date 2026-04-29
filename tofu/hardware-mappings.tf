# Cluster-level hardware mappings.
# These outlive any individual VM definition: keeping them in their own file
# means VMs that reference them can come and go without orphaning the mapping.

# Seagate 12TB USB backup drive
# Allows non-root API tokens to attach the device to VMs
resource "proxmox_virtual_environment_hardware_mapping_usb" "seagate_backup" {
  name    = "usb-seagate-backup"
  comment = "Seagate 12TB USB backup drive"

  map = [
    {
      id   = "0bc2:2038"
      node = var.pm_node_name
    },
  ]
}
