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

# asterism.quietlife.net -> Fly.io (cwage/asterism)
# NOT proxied: Fly terminates TLS with its own cert (fly certs add), and the
# cert validation needs to see the CNAME directly — proxying would also put
# Cloudflare in front of Fly's proxy for no benefit.
resource "cloudflare_record" "asterism" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "asterism"
  type    = "CNAME"
  content = "asterism.fly.dev"
  proxied = false
  comment = "asterism night-sky labeler on Fly.io"
}

# photos.chriswage.com -> GitHub Pages
resource "cloudflare_record" "photos_chriswage" {
  zone_id = data.cloudflare_zone.chriswage.zone_id
  name    = "photos"
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

resource "cloudflare_record" "xmpp1" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "xmpp"
  type    = "A"
  content = local.xmpp1_ipv4
  proxied = false
  comment = "xmpp1 Linode — Prosody + coturn"
}

# coturn shares the box; a separate name keeps the TURN realm stable if the
# TURN relay ever moves to its own host.
resource "cloudflare_record" "turn" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "turn"
  type    = "A"
  content = local.xmpp1_ipv4
  proxied = false
  comment = "coturn TURN relay for Jingle voice calls"
}

# HTTP upload (mod_http_file_share) — this is how MMS attachments and voice
# messages move. Served by Prosody on 443, so it must not be proxied either:
# Cloudflare would strip the client cert path and mangle large uploads.
resource "cloudflare_record" "xmpp_upload" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "upload"
  type    = "CNAME"
  content = "xmpp.quietlife.net"
  proxied = false
  comment = "Prosody mod_http_file_share (MMS attachments)"
}

# Multi-user chat component — JMP delivers group texts as MUCs.
resource "cloudflare_record" "xmpp_conference" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "conference"
  type    = "CNAME"
  content = "xmpp.quietlife.net"
  proxied = false
  comment = "Prosody MUC component (group texts)"
}

# Client-to-server discovery: tells Cheogram/Gajim where quietlife.net's
# XMPP server actually lives.
resource "cloudflare_record" "xmpp_srv_client" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-client._tcp"
  type    = "SRV"
  proxied = false

  data {
    service  = "_xmpp-client"
    proto    = "_tcp"
    name     = "quietlife.net"
    priority = 5
    weight   = 0
    port     = 5222
    target   = "xmpp.quietlife.net"
  }
}

# Server-to-server discovery: this is the record JMP's gateway follows to
# federate with us. If it is wrong, texts silently stop arriving.
resource "cloudflare_record" "xmpp_srv_server" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-server._tcp"
  type    = "SRV"
  proxied = false

  data {
    service  = "_xmpp-server"
    proto    = "_tcp"
    name     = "quietlife.net"
    priority = 5
    weight   = 0
    port     = 5269
    target   = "xmpp.quietlife.net"
  }
}

# The MUC component needs its own s2s SRV so remote servers can reach group chats.
resource "cloudflare_record" "xmpp_srv_server_conference" {
  zone_id = data.cloudflare_zone.quietlife.zone_id
  name    = "_xmpp-server._tcp.conference"
  type    = "SRV"
  proxied = false

  data {
    service  = "_xmpp-server"
    proto    = "_tcp"
    name     = "conference.quietlife.net"
    priority = 5
    weight   = 0
    port     = 5269
    target   = "xmpp.quietlife.net"
  }
}
