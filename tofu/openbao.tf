# OpenBao secrets management VM
# See issue #62 for architecture details

resource "proxmox_virtual_environment_vm" "openbao" {
  name      = "openbao"
  node_name = var.pm_node_name
  vm_id     = 103

  description = "OpenBao secrets management server"

  clone {
    vm_id = var.pm_template_id
  }

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "scsi0"
    size         = 20
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

  boot_order = ["scsi0"]

  lifecycle {
    ignore_changes = [initialization]
  }
}
