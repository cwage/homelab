terraform {
  # State lives on the NAS (NFS-mounted at /state inside the container).
  # Each workstation sets TOFU_STATE_PATH in .env to its local mount point.
  backend "local" {
    path = "/state/terraform.tfstate"
  }

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = false # Wildcard cert deployed via ansible proxmox_certs role

  ssh {
    agent = true
  }
}
