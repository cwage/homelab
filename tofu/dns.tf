# DNS server VM - NSD authoritative for lan.quietlife.net
# See docs/dns-plan.md for architecture details

resource "proxmox_virtual_environment_vm" "dns1" {
  name      = "dns1"
  node_name = var.pm_node_name
  vm_id     = 101

  description = "NSD authoritative DNS for lan.quietlife.net"

  clone {
    vm_id = var.pm_template_id
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
    interface    = "scsi0"
    size         = 8
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    datastore_id = var.pm_vm_datastore_id

    ip_config {
      ipv4 {
        address = "10.10.15.10/24"
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

  lifecycle {
    ignore_changes = [initialization]
  }
}
