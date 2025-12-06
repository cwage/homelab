# Container host VM - Docker host for running containerized apps
# GPU passthrough can be added later for transcoding workloads

resource "proxmox_virtual_environment_vm" "containers" {
  name      = "containers"
  node_name = var.pm_node_name
  vm_id     = 102

  description = "Docker host for containerized applications"

  clone {
    vm_id = var.pm_template_id
  }

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "scsi0"
    size         = 64
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

  lifecycle {
    ignore_changes = [initialization]
  }
}
