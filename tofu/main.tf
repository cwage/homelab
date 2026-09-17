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
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.0"
    }
    linode = {
      source  = "linode/linode"
      version = "~> 4.5"
    }
  }
}

# OpenBao (Vault-compatible) for secret retrieval
provider "vault" {
  # Reads VAULT_ADDR and VAULT_TOKEN from environment
  # (mapped from BAO_ADDR/BAO_TOKEN in docker-compose.yml)
  skip_child_token = true
}

provider "cloudflare" {
  api_token = ephemeral.vault_kv_secret_v2.cloudflare_tofu.data["api_token"]
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = false # Wildcard cert deployed via ansible proxmox_certs role

  ssh {
    agent = true
  }
}

# Linode API — token from OpenBao (ephemeral read in linode.tf)
provider "linode" {
  token = ephemeral.vault_kv_secret_v2.linode.data["api_token"]
}

# switch1 (MikroTik CRS310) REST API — creds from OpenBao (ephemeral read in switch.tf)
provider "routeros" {
  hosturl  = "https://${var.switch_mgmt_ip}"
  username = ephemeral.vault_kv_secret_v2.switch1.data["username"]
  password = ephemeral.vault_kv_secret_v2.switch1.data["password"]
  insecure = true # self-signed cert on the switch mgmt interface
}
