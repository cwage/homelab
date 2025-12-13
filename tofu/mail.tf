# Mail relay VM - ProtonMail Bridge for SMTP/IMAP
# Provides email relay for alerting and monitoring infrastructure

resource "proxmox_virtual_environment_vm" "mail" {
  name      = "mail"
  node_name = var.pm_node_name
  vm_id     = 104

  description = "ProtonMail Bridge relay for alerting/monitoring"

  clone {
    vm_id = var.pm_template_id
  }

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 1024
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
        address = "10.10.15.14/24"
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

  boot_order = ["scsi0"]

  lifecycle {
    ignore_changes = [initialization]
  }
}
