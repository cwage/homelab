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
      version = "~> 4.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.0"
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
  api_token = data.vault_kv_secret_v2.cloudflare_tofu.data["api_token"]
}

provider "proxmox" {
  endpoint  = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = false # Wildcard cert deployed via ansible proxmox_certs role

  ssh {
    agent = true
  }
}
