# Cloudflare DNS and Tunnel management
# Credentials are fetched from OpenBao at kv/infra/cloudflare/tofu

# Fetch Cloudflare credentials from OpenBao. Two reads of the same secret on
# purpose: the ephemeral one feeds the provider api_token and is never
# written to state; the data source stays for account_id, which lands on
# ordinary resource attributes that can't take ephemeral values.
ephemeral "vault_kv_secret_v2" "cloudflare_tofu" {
  mount = "kv"
  name  = "infra/cloudflare/tofu"
}

data "vault_kv_secret_v2" "cloudflare_tofu" {
  mount = "kv"
  name  = "infra/cloudflare/tofu"
}

# Look up zones by name — add more as needed. (Provider v5: lookups go
# through a filter object, and record names below are fully qualified.)
data "cloudflare_zone" "quietlife" {
  filter = { name = "quietlife.net" }
}

data "cloudflare_zone" "chriswage" {
  filter = { name = "chriswage.com" }
}

# asterism.quietlife.net -> Fly.io (cwage/asterism)
# NOT proxied: Fly terminates TLS with its own cert (fly certs add), and the
# cert validation needs to see the CNAME directly — proxying would also put
# Cloudflare in front of Fly's proxy for no benefit.
resource "cloudflare_dns_record" "asterism" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "asterism.quietlife.net"
  ttl     = 1
  type    = "CNAME"
  content = "asterism.fly.dev"
  proxied = false
  comment = "asterism night-sky labeler on Fly.io"
}

# photos.chriswage.com -> GitHub Pages
resource "cloudflare_dns_record" "photos_chriswage" {
  zone_id = data.cloudflare_zone.chriswage.zone_id
  name    = "photos.chriswage.com"
  ttl     = 1
  type    = "CNAME"
  content = "cwage.github.io"
  proxied = true
}

# ---------------------------------------------------------------------------
# XMPP (see docs/xmpp.md)
#
# The JID domain is the bare `quietlife.net`, but the server itself lives at
# xmpp.quietlife.net. Clients and peer servers find it via the SRV records
# below, so this does NOT disturb the existing A record for the website.
#
# None of these are proxied — Cloudflare's proxy only handles HTTP(S), and XMPP
# c2s/s2s are raw TCP on 5222/5269. Proxying would black-hole them.
# ---------------------------------------------------------------------------

resource "cloudflare_dns_record" "xmpp1" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "xmpp.quietlife.net"
  ttl     = 1
  type    = "A"
  content = local.xmpp1_ipv4
  proxied = false
  comment = "xmpp1 Linode — Prosody + coturn"
}

# coturn shares the box; a separate name keeps the TURN realm stable if the
# TURN relay ever moves to its own host.
resource "cloudflare_dns_record" "turn" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "turn.quietlife.net"
  ttl     = 1
  type    = "A"
  content = local.xmpp1_ipv4
  proxied = false
  comment = "coturn TURN relay for Jingle voice calls"
}

# HTTP upload (mod_http_file_share) — this is how MMS attachments and voice
# messages move. Served by Prosody on 443, so it must not be proxied either:
# Cloudflare would strip the client cert path and mangle large uploads.
resource "cloudflare_dns_record" "xmpp_upload" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "upload.quietlife.net"
  ttl     = 1
  type    = "CNAME"
  content = "xmpp.quietlife.net"
  proxied = false
  comment = "Prosody mod_http_file_share (MMS attachments)"
}

# Multi-user chat component — JMP delivers group texts as MUCs.
resource "cloudflare_dns_record" "xmpp_conference" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "conference.quietlife.net"
  ttl     = 1
  type    = "CNAME"
  content = "xmpp.quietlife.net"
  proxied = false
  comment = "Prosody MUC component (group texts)"
}

# Client-to-server discovery: tells Cheogram/Gajim where quietlife.net's
# XMPP server actually lives.
resource "cloudflare_dns_record" "xmpp_srv_client" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-client._tcp.quietlife.net"
  type    = "SRV"
  ttl     = 1
  proxied = false
  # v5 reads the SRV priority back at the top level as well as in data;
  # set both or every plan shows a spurious in-place update.
  priority = 5

  data = {
    priority = 5
    weight   = 0
    port     = 5222
    target   = "xmpp.quietlife.net"
  }
}

# Server-to-server discovery: this is the record JMP's gateway follows to
# federate with us. If it is wrong, texts silently stop arriving.
resource "cloudflare_dns_record" "xmpp_srv_server" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-server._tcp.quietlife.net"
  type    = "SRV"
  ttl     = 1
  proxied = false
  # v5 reads the SRV priority back at the top level as well as in data;
  # set both or every plan shows a spurious in-place update.
  priority = 5

  data = {
    priority = 5
    weight   = 0
    port     = 5269
    target   = "xmpp.quietlife.net"
  }
}

# The MUC component needs its own s2s SRV so remote servers can reach group chats.
resource "cloudflare_dns_record" "xmpp_srv_server_conference" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-server._tcp.conference.quietlife.net"
  type    = "SRV"
  ttl     = 1
  proxied = false
  # v5 reads the SRV priority back at the top level as well as in data;
  # set both or every plan shows a spurious in-place update.
  priority = 5

  data = {
    priority = 5
    weight   = 0
    port     = 5269
    target   = "xmpp.quietlife.net"
  }
}

# --- Cloudflare Access: calibre.quietlife.net -------------------------------
#
# THIS IS THE ENTIRE SECURITY BOUNDARY for Calibre-Web. That app runs with
# anonymous browsing on, so it serves the whole library to any request that
# reaches it. Delete this application, set its policy to bypass, or add a
# Traefik route or published port to the container, and the library is
# world-readable. See docs/calibre.md.
#
# Scope note: only the Access application and its policy are managed here.
# Tunnel ingress routes stay in the Zero Trust dashboard -- adopting
# cloudflare_tunnel_config would take ownership of ALL routes for the tunnel,
# silently dropping jellyfin and pad/pad-sandbox unless every one of them were
# redeclared in this file.
#
# Adding a reader: update the allowed_emails list in OpenBao (see
# docs/calibre.md), then apply. Nothing is provisioned in Calibre-Web.
#
# The reader allowlist lives in OpenBao, NOT in a variable or tfvars: this
# repo is public, and friends' email addresses don't belong in it. The value
# is a single comma-separated string (KV v2 stores strings), split below.
data "vault_kv_secret_v2" "calibre_access" {
  mount = "kv"
  name  = "infra/cloudflare/calibre-access"
}

resource "cloudflare_zero_trust_access_application" "calibre" {
  account_id = data.vault_kv_secret_v2.cloudflare_tofu.data["account_id"]
  name       = "Calibre-Web"
  domain     = "calibre.quietlife.net"
  type       = "self_hosted"

  # A week between PIN prompts. Readers open this occasionally, and the point
  # was to stop handing people passwords -- a short session just means more
  # PIN emails for no security gain.
  session_duration = "168h"

  app_launcher_visible      = true
  auto_redirect_to_identity = false

  # Pinned to the live values so the v5 import is a no-op: the provider
  # defaults http_only_cookie_attribute to true, which the app never had.
  http_only_cookie_attribute = false
  enable_binding_cookie      = false
  options_preflight_bypass   = false

  # Provider v5: policies attach to the application from this side (the
  # policy resource is standalone and reusable), replacing the old
  # application_id + precedence on the policy.
  policies = [{
    id         = cloudflare_zero_trust_access_policy.calibre_allow.id
    precedence = 1
  }]
}

resource "cloudflare_zero_trust_access_policy" "calibre_allow" {
  account_id = data.vault_kv_secret_v2.cloudflare_tofu.data["account_id"]
  name       = "Allow known readers"
  decision   = "allow"

  # Only these addresses can complete the one-time-PIN login. This list is
  # the whole access-control surface: Calibre-Web itself has anonymous
  # browsing on and will serve the library to anyone Access lets through.
  # (An earlier iteration used `everyone = true` -- any mailbox could get a
  # PIN -- but that made the hostname the only real secret.)
  include = [
    for e in split(",", data.vault_kv_secret_v2.calibre_access.data["allowed_emails"]) :
    { email = { email = e } }
  ]
}
