# Linode VPS instances
#
# Credentials are fetched from OpenBao at kv/infra/linode (see docs/openbao-secrets.md).
# Create the token in the Linode Cloud Manager UI and write it to OpenBao
# yourself — never generate it through tooling that echoes the value.
#
# Required scopes:
#   Linodes:   Read/Write   create, delete, and resize instances
#   Firewalls: Read/Write   the Cloud Firewall below
#   Events:    Read Only    NOT optional. Every async operation (create, delete,
#                           resize, boot) is tracked by polling /account/events.
#                           Without it, creates succeed but deletes and resizes
#                           fail with "[401] Your OAuth token is not authorized
#                           to use this endpoint" — after the operation has been
#                           issued, which is a confusing place to fail.
#   Account:   Read Only    account-level lookups
#
# Linode does not allow editing an existing token's scopes; a scope change means
# issuing a new token and revoking the old one.
#
# Historically the Linodes (felix, gaming1, the retired turn box) were created by
# hand and only adopted into Ansible afterwards. xmpp1 is the first one managed
# here. To bring the existing boxes under OpenTofu without recreating them, add a
# resource block matching their current config and import it:
#
#   make tofu-run ARGS='import linode_instance.felix <linode-id>'
#
# Do NOT add felix/gaming1 resource blocks without importing first — a plain apply
# would try to create duplicates.

data "vault_kv_secret_v2" "linode" {
  mount = "kv"
  name  = "infra/linode"
}

variable "linode_region" {
  description = "Linode region for new instances (us-ord = Chicago, closest well-provisioned DC to Nashville)"
  type        = string
  default     = "us-ord"
}

variable "linode_xmpp_type" {
  description = "Linode instance type for the XMPP host."
  type        = string

  # NOT a Nanode. Prosody and coturn would run fine in 1GB, but nixos-anywhere
  # installs by kexec'ing a NixOS installer image into RAM, and that OOMs on a
  # 1GB host before it can repartition. 2GB is the practical floor for any
  # nixos-anywhere target, and it leaves the SQLite MAM archive some headroom.
  default = "g6-standard-1"
}

# xmpp1 — Prosody XMPP server + coturn TURN relay for JMP/Cheogram voice calls.
#
# This box is deliberately OUTSIDE the LAN: it is the only internet-facing
# listener in the fleet, so it must not sit on 10.10.15.0/24 alongside OpenBao,
# the NAS, and Proxmox. See docs/xmpp.md for the rationale.
resource "linode_instance" "xmpp1" {
  label  = "xmpp1"
  region = var.linode_region
  type   = var.linode_xmpp_type

  # This box runs NixOS, but Linode has no NixOS image. Ubuntu is only ever a
  # kexec target for nixos-anywhere, which repartitions via disko and installs
  # over it — nothing from this image survives. See docs/xmpp.md.
  image      = "linode/ubuntu24.04"
  private_ip = false

  # Root password from OpenBao. Ansible takes over user management immediately
  # after provisioning (the `users` role), so this is only ever used for console
  # recovery via Lish.
  root_pass = data.vault_kv_secret_v2.linode.data["xmpp1_root_pass"]

  authorized_keys = [
    trimspace(file("${path.module}/../ansible/keys/deploy.pub")),
    trimspace(file("${path.module}/../ansible/inventories/keys/cwage-portaplotz.pub")),
    trimspace(file("${path.module}/../ansible/inventories/keys/cwage-portaptty.pub")),
    trimspace(file("${path.module}/../ansible/inventories/keys/cwage-shot.pub")),
  ]

  tags = ["xmpp", "ansible-managed"]

  # The root password is only consumed at build time; Linode does not expose it
  # back, so a rotation in OpenBao should not force a rebuild of the instance.
  lifecycle {
    ignore_changes = [root_pass]
  }
}

# Linode Cloud Firewall for xmpp1.
#
# Default-deny inbound, declared here rather than with ufw/nftables on the host
# so the ruleset is reviewable in the repo and applies even if the box is
# rebuilt or the host firewall is misconfigured. Everything opened below is a
# service that genuinely has to be reachable from the public internet; see
# docs/xmpp.md for what each one carries.
resource "linode_firewall" "xmpp1" {
  label           = "xmpp1-fw"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
  linodes         = [linode_instance.xmpp1.id]

  # ICMP, both families. Not optional politeness: IPv6 REQUIRES inbound ICMPv6
  # for neighbor discovery and router advertisements — with a DROP inbound
  # policy and no ICMP rule, the box gets a SLAAC address that silently black-
  # holes, and anything that prefers v6 (e.g. lego's DNS propagation checks
  # against Cloudflare's nameservers) times out. Linode's own docs warn about
  # exactly this. Also restores ping for monitoring.
  inbound {
    label    = "icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # DHCP replies from Linode's infrastructure. Without this, a DROP inbound
  # policy silently eats the DHCPOFFER/ACK and the guest never gets an IPv4
  # address — which presents as "instance running, nothing answering" and is
  # nearly indistinguishable from a boot failure. (Fresh images dodge it by
  # DHCPing in the window before firewall_apply lands; a reboot after that
  # window hangs forever.) Cost four install cycles to identify.
  inbound {
    label    = "dhcp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "67,68"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22,5344"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # HTTP upload (MMS attachments), BOSH, and websockets for the eventual
  # Converse.js web client.
  inbound {
    label    = "https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # XMPP client-to-server.
  inbound {
    label    = "xmpp-c2s"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "5222"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # XMPP server-to-server — this is the one JMP's gateway uses. Blocking it
  # means texts silently stop arriving.
  inbound {
    label    = "xmpp-s2s"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "5269"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "turn-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "3478,5349"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "turn-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "3478,5349"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # coturn relay range — must match coturn_relay_port_{min,max} in the coturn
  # role defaults. Voice call audio flows through here.
  inbound {
    label    = "turn-relay"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "49152-49200"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }
}

# linode_instance.ip_address is deprecated in provider v2 in favour of the ipv4
# set. The instance is created with private_ip = false, so that set holds
# exactly one address — the public one.
locals {
  xmpp1_ipv4 = tolist(linode_instance.xmpp1.ipv4)[0]
}

output "xmpp1_ip" {
  description = "Public IPv4 of xmpp1 — set this as ansible_host in inventories/hosts.yml"
  value       = local.xmpp1_ipv4
}
