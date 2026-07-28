# containers: NixOS Docker host with GTX 1050 Ti GPU and Seagate USB
# passthrough.

resource "proxmox_virtual_environment_vm" "containers" {
  name      = "containers"
  node_name = var.pm_node_name
  vm_id     = 152

  description = "Docker host (NixOS)"

  clone {
    vm_id = var.pm_nixos_template_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  machine = "q35" # Required for PCIe passthrough (VFIO)

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "virtio0"
    size         = 64
  }

  # Seagate 12TB USB backup drive passthrough
  # Uses USB mapping (like GPU PCI mapping) so non-root API tokens can manage it
  usb {
    mapping = proxmox_virtual_environment_hardware_mapping_usb.seagate_backup.name
    usb3    = true
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
        address = "10.10.15.11/24"
        gateway = "10.10.15.1"
      }
    }

    dns {
      domain  = "lan.quietlife.net"
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

  boot_order = ["virtio0"]

  lifecycle {
    ignore_changes = [initialization]
  }
}
