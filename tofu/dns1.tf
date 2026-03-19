# DNS server VM — NixOS with NSD authoritative for lan.quietlife.net

resource "proxmox_virtual_environment_vm" "dns1" {
  name      = "dns1"
  node_name = var.pm_node_name
  vm_id     = 150

  description = "NSD authoritative DNS for lan.quietlife.net (NixOS)"

  clone {
    vm_id = var.pm_nixos_template_id
  }

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "virtio0"
    size         = 8
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.pm_vm_datastore_id

    ip_config {
      ipv4 {
        address = "10.10.15.15/24"
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
