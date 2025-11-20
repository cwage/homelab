locals {
  debian_bookworm_cloud_image = {
    # Proxmox download API wants .iso/.img extensions for iso content
    file_name = "debian-12-genericcloud-amd64.img"
    url       = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    format    = "qcow2" # Source image format; name stays .img to satisfy API
  }
}

resource "proxmox_virtual_environment_download_file" "debian_bookworm" {
  content_type = "iso"
  datastore_id = var.pm_image_datastore_id
  file_name    = local.debian_bookworm_cloud_image.file_name
  node_name    = var.pm_node_name
  url          = local.debian_bookworm_cloud_image.url
}
