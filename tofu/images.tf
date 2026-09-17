locals {
  debian_bookworm_cloud_image = {
    # Proxmox download API wants .iso/.img extensions for iso content
    # Using 'generic' (not 'genericcloud') for full kernel with hardware
    # driver support (USB passthrough, GPU passthrough, etc.)
    file_name = "debian-12-generic-amd64.img"
    url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
    format    = "qcow2" # Source image format; name stays .img to satisfy API
  }
}

resource "proxmox_download_file" "debian_bookworm" {
  content_type = "iso"
  datastore_id = var.pm_image_datastore_id
  file_name    = local.debian_bookworm_cloud_image.file_name
  node_name    = var.pm_node_name
  url          = local.debian_bookworm_cloud_image.url

  # The URL points at Debian's rolling "latest" image, so its size changes
  # every time they republish. Without this, each republish makes the plan
  # want to destroy and re-download the file (a spurious destroy in every
  # plan). VMs are clones; they don't depend on this file after creation.
  overwrite = false
}

# bpg/proxmox renamed the resource (the old name goes away at their 1.0).
moved {
  from = proxmox_virtual_environment_download_file.debian_bookworm
  to   = proxmox_download_file.debian_bookworm
}
