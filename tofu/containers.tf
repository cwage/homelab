# Container host VM - Docker host for running containerized apps
# With GTX 1050 Ti GPU passthrough for hardware transcoding

resource "proxmox_virtual_environment_vm" "containers" {
  name      = "containers"
  node_name = var.pm_node_name
  vm_id     = 102

  description = "Docker host for containerized applications with GPU passthrough"

  clone {
    vm_id = var.pm_template_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  machine = "q35"

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "scsi0"
    size         = 64
  }

  # GTX 1050 Ti GPU passthrough (IOMMU Group 14)
  # Uses PCI mapping defined in /etc/pve/mapping/pci.cfg
  hostpci {
    device  = "hostpci0"
    mapping = "gpu-gtx1050ti"
    pcie    = true
    rombar  = true
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.pm_vm_datastore_id

    ip_config {
      ipv4 {
        address = "10.10.15.12/24"
        gateway = "10.10.15.1"
      }
    }

    dns {
      servers = ["10.10.15.1"]
    }

    user_account {
      username = "deploy"
      keys     = [trimspace(file("${path.module}/../ansible/keys/deploy.pub"))]
    }
  }

  agent {
    enabled = true
  }

  boot_order = ["scsi0"]

  lifecycle {
    ignore_changes = [initialization]
  }
}
