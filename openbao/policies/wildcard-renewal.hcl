# Attach only to the containers host's existing AppRole (containers2).
path "kv/data/infra/cloudflare" {
  capabilities = ["read"]
}

path "kv/data/infra/certs/lan.quietlife.net" {
  capabilities = ["read", "update"]
}
