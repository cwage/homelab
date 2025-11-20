locals {
  cwage_ssh_pubkey = trimspace(file("${path.module}/../ansible/inventories/keys/cwage-portaptty.pub"))

  test_vm = {
    name        = "vm-test-01"
    description = "Debian 12 cloud-init test VM"
    tags        = ["test", "debian12", "cloudinit"]
    cpu_cores   = 2
    memory_mb   = 2048
    disk_gb     = 20
  }
}

resource "proxmox_virtual_environment_vm" "test_vm" {
  name        = local.test_vm.name
  description = local.test_vm.description
  tags        = local.test_vm.tags
  node_name   = var.pm_node_name
  on_boot     = true
  started     = true

  clone {
    vm_id        = var.pm_debian12_template_id
    full         = true
    datastore_id = var.pm_vm_datastore_id
  }

  cpu {
    sockets = 1
    cores   = local.test_vm.cpu_cores
    type    = "x86-64-v2-AES"
  }

  memory {
    dedicated = local.test_vm.memory_mb
  }

  boot_order = ["scsi0"]

  disk {
    interface = "scsi0"
    size      = local.test_vm.disk_gb
  }

  network_device {
    bridge = var.pm_lan_bridge
    model  = "virtio"
    mac_address = "02:00:10:10:0f:37"
  }

  initialization {
    datastore_id = var.pm_vm_datastore_id

    user_account {
      username = "cwage"
      keys     = [local.cwage_ssh_pubkey]
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}
