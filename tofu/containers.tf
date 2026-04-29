# Legacy Debian-based Docker host. As of #132 phase 2 it's powered off and
# kept only as a rollback target — GPU and USB passthrough moved to
# containers2 (10.10.15.11), and DNS for service CNAMEs (jellyfin/sonarr/etc.)
# now points at containers2. Removed in a follow-up once containers2 is
# trusted enough that we don't need the parachute.
#
# The Seagate USB hardware mapping that was previously defined here was moved
# to tofu/hardware-mappings.tf so it survives the eventual deletion of this
# resource.

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

  machine = "q35" # Required for PCIe passthrough (VFIO)

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.pm_vm_datastore_id
    interface    = "scsi0"
    size         = 64
  }

  # GPU and USB passthrough moved to containers2 at cutover (#132 phase 2).
  # See the file-level comment above for the broader retirement plan.

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

  # Powered off post-cutover; kept defined as a rollback target only.
  # Removed in a follow-up PR once containers2 is fully trusted.
  started = false

  # Prevent Tofu from recreating the VM when cloud-init config drifts
  # after initial provisioning. Ansible manages config from here on.
  lifecycle {
    ignore_changes = [initialization]
  }
}
