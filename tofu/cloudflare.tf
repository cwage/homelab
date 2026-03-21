# Cloudflare DNS and Tunnel management
# Credentials are fetched from OpenBao at kv/infra/cloudflare/tofu

# Fetch Cloudflare credentials from OpenBao
data "vault_kv_secret_v2" "cloudflare_tofu" {
  mount = "kv"
  name  = "infra/cloudflare/tofu"
}

locals {
  cf_account_id = data.vault_kv_secret_v2.cloudflare_tofu.data["account_id"]
}

# Look up zones by name — add more as needed
data "cloudflare_zone" "quietlife" {
  name = "quietlife.net"
}
