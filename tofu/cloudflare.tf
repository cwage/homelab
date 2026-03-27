# Cloudflare DNS and Tunnel management
# Credentials are fetched from OpenBao at kv/infra/cloudflare/tofu

# Fetch Cloudflare credentials from OpenBao
data "vault_kv_secret_v2" "cloudflare_tofu" {
  mount = "kv"
  name  = "infra/cloudflare/tofu"
}

# Look up zones by name — add more as needed
data "cloudflare_zone" "quietlife" {
  name = "quietlife.net"
}

data "cloudflare_zone" "chriswage" {
  name = "chriswage.com"
}

# photos.chriswage.com -> GitHub Pages
resource "cloudflare_record" "photos_chriswage" {
  zone_id = data.cloudflare_zone.chriswage.zone_id
  name    = "photos"
  type    = "CNAME"
  content = "cwage.github.io"
  proxied = true
}
