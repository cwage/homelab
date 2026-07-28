# XMPP (Prosody) — self-hosted Jabber for a JMP phone number

Prosody + coturn on a public Linode (`xmpp1`), running NixOS. Holds the Jabber
account that [JMP](https://jmp.chat) federates with; JMP bridges a real phone
number to XMPP, and this server is the account that number is delivered to.

Practically: a Google Voice replacement where the number lives with JMP but the
message archive, the identity, and client access all belong to us.

## Why this is not on the LAN

Everything else exposed to the internet goes out through the Cloudflare Tunnel,
which is outbound-only — nothing at home listens. XMPP cannot work that way:
server-to-server federation is raw TCP on 5269, and JMP's servers must be able
to open a connection *to* us. That means a real inbound listener.

`10.10.15.0/24` is flat. Proxmox only exposes `vmbr0`, so a host there sits on
the same segment as OpenBao, the NAS, and the hypervisor — and same-subnet
traffic never traverses `fw1`, so no pf rule can contain it. An internet-facing
daemon there would be a foothold next to the secrets store.

A DMZ VLAN at home, which `switch1` is capable of, remains a future option. It
is a prerequisite for hosting anything internet-facing on the LAN, not just
this.

## How xmpp1 differs from every other NixOS host

Two deliberate deviations, both forced by being off-LAN:

| | LAN hosts (dns1, bao, containers) | xmpp1 |
|---|---|---|
| **Install** | Clone Proxmox VMA template 9001 | `nixos-anywhere` + `disko` |
| **Secrets** | `openbao-agent` (AppRole, CIDR-bound) | `sops-nix` (age, in-repo) |
| **Firewall** | Disabled; pf on fw1 handles it | Host firewall **on**, plus Linode Cloud Firewall |

The secrets difference is the important one. `modules/openbao-agent.nix`
authenticates with an AppRole CIDR-bound to a static LAN address and talks to
`bao.lan.quietlife.net:8200`. xmpp1 can reach neither, and exposing OpenBao to
the internet would undo the whole reason this box is off-LAN. So its secrets are
age-encrypted in `secrets/xmpp1.yaml` and decrypted at activation using the
host's own SSH key. See [secrets/README.md](../secrets/README.md).

OpenBao stays canonical; the sops file is a copy for a host that cannot reach it.

## Identity and portability

The JID domain is the bare apex (`cwage@quietlife.net`) while the server runs at
`xmpp.quietlife.net`. Clients and peer servers bridge the two via SRV records.

This is the future-proofing argument: the identity is bound to the *domain*,
which we own, not to the server. If this box dies or self-hosting stops being
worth it, re-point the SRV records at a different host — or a hosted provider —
and the JID never changes. Contacts notice nothing. Only the MAM archive would
need migrating. Same model as SMTP: own the domain, rent or run the server, stay
portable.

## Architecture

```
        JMP gateway (cheogram.com)
                 │  XMPP s2s :5269
                 ▼
   ┌─────────────────────────────┐
   │  xmpp1 (Linode, NixOS)      │
   │                             │
   │  prosody   :5222 c2s        │  ← Cheogram (Android), Gajim, Converse.js
   │            :5269 s2s        │  ← JMP + the rest of the XMPP federation
   │            :443  upload/ws  │  ← MMS attachments, websockets
   │                             │
   │  coturn    :3478 / :5349    │  ← Jingle RTP relay for voice calls
   │            :49152-49200/udp │
   └─────────────────────────────┘

  Home LAN listens on nothing.
```

| Component | Role |
|---|---|
| `services.prosody` | XMPP server: c2s, s2s, MAM archive, MUC, HTTP upload |
| `services.coturn` | TURN/STUN relay so Jingle voice calls traverse NAT |
| `security.acme` | Let's Encrypt via Cloudflare DNS-01, auto-renewing |
| JMP | Holds the phone number; SMS/MMS/voice/voicemail-transcription gateway |

## Certificates

DNS-01 is the only workable challenge: the JID domain is the bare apex, whose A
record points at the website rather than this box. `security.acme` handles
issuance and renewal via systemd timers — an expired cert here means federation
stops and text messages stop arriving.

The Cloudflare token is a **separate** token from the one tofu uses, scoped to
the `quietlife.net` zone only with `Zone:Read` + `DNS:Edit`. It lives in
`secrets/xmpp1.yaml` as `acme-cloudflare-env`, consumed as a systemd
`EnvironmentFile`.

Both prosody and coturn read the cert via the shared `xmppsvc` group rather than
by loosening file modes. `reloadServices` restarts both on renewal — coturn only
reads certificates at startup.

A future hardening step is acme-dns: delegate only
`_acme-challenge.quietlife.net` by CNAME, so the token can create nothing but
challenge records.

## Secrets and credentials

| Where | What | Used by |
|---|---|---|
| `kv/infra/linode` | `api_token`, `xmpp1_root_pass` | `tofu/linode.tf` |
| `kv/infra/cloudflare/acme-vps` | `api_token` (zone-scoped) | certbot/lego DNS-01 |
| `kv/infra/coturn/auth` | `secret` | prosody `turn_external_secret` + coturn |
| `kv/infra/users/cwage` | `password_hash` | the `cwage` account |
| `secrets/xmpp1.yaml` | encrypted copies of the last three | xmpp1 at activation |
| `~/.config/sops/age/keys.txt` | your age private key | editing `secrets/xmpp1.yaml` |

OpenBao stays canonical. `secrets/xmpp1.yaml` is an encrypted copy for a host
that cannot reach it — rotate a value in OpenBao and you must rotate it there
too.

**Back up `~/.config/sops/age/keys.txt`** (Bitwarden, alongside the OpenBao root
token). It is the only way to decrypt `secrets/xmpp1.yaml`. Losing it is
recoverable — regenerate the values from OpenBao and re-encrypt — but tedious.

### Linode API token scopes

| Scope | Level | Why |
|---|---|---|
| Linodes | Read/Write | create, delete, resize instances |
| Firewalls | Read/Write | the Cloud Firewall |
| **Events** | **Read Only** | **easy to miss — see below** |
| Account | Read Only | account-level lookups |

`Events` fails in a genuinely confusing way. The provider polls
`/account/events` to track every async operation, so *creating* an instance
works fine without it, but deleting or resizing one dies partway through with
`[401] Your OAuth token is not authorized to use this endpoint` — pointing at
the operation rather than at the missing scope.

Linode cannot edit an existing token's scopes, so fixing this means issuing a
new token and revoking the old one.

## Bootstrap

### 1. Provision the instance

```bash
make tofu-plan          # READ THE PLAN — nothing should be destroyed
make tofu-apply
```

Note the `xmpp1_ip` output. Tofu creates the Linode with a stock Ubuntu image;
that image is only ever a kexec target for the NixOS installer and is discarded.

### 2. Prepare secrets

The remaining steps use `nix run`, which needs flakes enabled. They are off by
default in the workstation's `nix.conf`, so either enable them permanently:

```bash
mkdir -p ~/.config/nix && echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

…or export this for the session and leave the global config alone:

```bash
export NIX_CONFIG='experimental-features = nix-command flakes'
```

sops-nix needs the host's age key, which is derived from its SSH host key. To
avoid a chicken-and-egg on first deploy, generate the host key locally and hand
it to the installer:

```bash
mkdir -p /tmp/xmpp1-etc/etc/ssh
ssh-keygen -t ed25519 -N "" -f /tmp/xmpp1-etc/etc/ssh/ssh_host_ed25519_key
nix run nixpkgs#ssh-to-age -- -i /tmp/xmpp1-etc/etc/ssh/ssh_host_ed25519_key.pub
```

Put that age public key into `.sops.yaml` as `host_xmpp1`.

You also need an admin key so *you* can edit secrets. Derive it from a personal
**ed25519** SSH key (RSA keys cannot be converted):

```bash
mkdir -p ~/.config/sops/age
nix run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
nix run nixpkgs#ssh-to-age -- -i ~/.ssh/id_ed25519.pub
```

The last command prints the public half — that goes into `.sops.yaml` as
`admin_cwage`. sops finds the private half at `~/.config/sops/age/keys.txt`
automatically.

Then create the encrypted secrets:

```bash
nix run nixpkgs#sops -- secrets/xmpp1.yaml
```

Expected keys are documented in [secrets/README.md](../secrets/README.md).
`coturn-auth-secret` and `cwage-password-hash` should match the values already
in OpenBao at `kv/infra/coturn/auth` and `kv/infra/users/cwage`.

### 3. Install NixOS

```bash
nix run github:nix-community/nixos-anywhere -- --flake .#xmpp1 --extra-files /tmp/xmpp1-etc root@<xmpp1-ip>
rm -rf /tmp/xmpp1-etc
```

`--extra-files` places the pre-generated SSH host key before first boot, so
sops-nix can decrypt on the very first activation.

### 4. Subsequent deploys

```bash
make nix-deploy-host HOST=xmpp1 TARGET=<xmpp1-ip>
```

### 5. Create the account

Deliberately manual — automating it would mean a password in the repo.

```bash
ssh -i ansible/keys/deploy deploy@<xmpp1-ip>
sudo prosodyctl adduser cwage@quietlife.net
```

### 6. Verify before trusting it with a phone number

```bash
sudo prosodyctl check
sudo prosodyctl check dns
sudo prosodyctl check certs
```

The [XMPP compliance tester](https://compliance.conversations.im/) is a good
external check — it flags missing SRV records, cert problems, and absent mobile
modules.

## Signing up with JMP

1. Log into the new JID from [Cheogram](https://cheogram.com/) (Android) or Gajim.
2. On the JMP signup page choose *"I already have a Jabber ID"* and give
   `cwage@quietlife.net`.
3. Take the **temporary** number first.

New JMP accounts generally must *receive* a text from a real person before they
can send or place calls — have someone text the temp number early, or it looks
broken.

**Live on the temp number for ~two weeks before porting.** Check push
notification reliability, message delivery latency, and whether MMS works with
the people you actually text. Porting out of Google Voice costs $3 to unlock and
is effectively one-way, so the trial is the point.

## Web client

The Google-Voice-in-a-browser equivalent is [Converse.js](https://conversejs.org)
at **https://chat.lan.quietlife.net** — log in as `cwage` (the domain is locked
to `quietlife.net`) with the prosody account password.

How it hangs together:

- There is no official Converse.js Docker image, so instead of trusting a
  third-party build, the official release tarball is fetched (pinned by hash)
  as a nix derivation in `hosts/containers/configuration.nix` and served by a
  stock nginx container (`converse` in the compose stack) behind Traefik.
- The page is pure static files. The chat connection is a websocket to
  `wss://chat.lan.quietlife.net/xmpp-websocket` — **same origin as the page**,
  terminated by Traefik under the LAN wildcard cert and reverse-proxied to
  prosody on xmpp1 (`converse-ws` router in `stacks/traefik-tls.yml`).
- **Why not connect to the box directly?** The browser *can't*. Prosody selects
  its TLS certificate by XMPP *identity* — the name a client asks for via SNI —
  and its identity is the apex `quietlife.net`. `xmpp.quietlife.net` is only a
  connection hostname (a DNS pointer to the box), not a VirtualHost, so a
  browser opening `wss://xmpp.quietlife.net/...` sends an SNI prosody has no
  cert context for and the TLS handshake is refused (`unrecognized_name`).
  Native clients (Cheogram) dodge this because they ask for the identity
  `quietlife.net` over TLS even though DNS routes them to the box. Traefik
  bridges the gap: it presents SNI `quietlife.net` on the backend connection
  (`prosody-backend` serversTransport), a name prosody *does* serve, and
  forwards the request with `http_default_host` on prosody catching the
  unmatched Host header. Nothing on the public box needs changing.
- **LAN-only, on purpose.** Off-LAN texting is what Cheogram on the phone is
  for; exposing this page publicly would just put a login form for the XMPP
  account on the internet. It also means the web client dies with the homelab —
  acceptable, because the phone path (Cheogram → prosody on the VPS → JMP) does
  not touch the homelab at all.
- Because prosody keeps the full archive (`mam`, never expires) and `carbons`
  is on, the web client and the phone both see the complete conversation
  history regardless of which one sent a message.

Upgrading Converse.js is a version + hash bump in
`hosts/containers/configuration.nix`; after deploying, recreate the container
(`docker compose up -d --force-recreate converse`) since the bind-mount
source path doesn't change.

## Debugging calls

Voice calls have two planes and only one of them touches this box. All
**signaling** (ring, accept, hang up, and the ICE negotiation where both ends
exchange candidate addresses) flows through prosody as Jingle stanzas. The
**media** (RTP audio) then takes the best direct path — for JMP calls that is
usually phone ↔ Cheogram's public media gateway, bypassing xmpp1 entirely.
coturn is the relay of last resort, used only when ICE can't find a working
direct pair, so an idle coturn during a working call is normal. The corollary:
a call that sets up fine but loses audio mid-call usually broke on a path we
don't carry — first suspects are the client-side NAT (a UDP mapping getting
remapped mid-flow turns into one-way audio: the media server drops RTP from
the unrecognized new source, while the old inbound mapping keeps working) and
JMP's SIP leg.

What the logs give you while shaking this out:

- `journalctl -u prosody` — with `stanzadebug` loaded (see
  `hosts/xmpp1/configuration.nix`), the *complete* Jingle payloads:
  session-initiate/accept, every ICE candidate offered, transport-info,
  session-terminate with reason. Without it, prosody's debug log records only
  stanza envelopes, which is useless for call forensics. `stanzadebug` also
  puts message bodies in the journal — it is a debugging aid to remove once
  calling is trusted.
- `journalctl -u coturn` — `verbose` + `log-binding` + `syslog` mean every
  STUN binding request and TURN allocation (with client address, refreshes,
  per-peer permissions) lands in the journal. If a client never even STUNs
  us during call setup, it isn't gathering our relay candidates — check that
  `turn_external` is advertising correctly (`prosodyctl check turn`, which
  does a live allocation against coturn).
- The phone's XMPP TCP session (`journalctl -u prosody | grep '<conn-id>'`)
  doubles as a network-change detector: a WiFi↔cellular hop severs it and
  leaves a smacks hibernate/resume trail with the new source IP. A continuous
  session with the same source port proves the phone never changed networks —
  which is how the first one-way-audio investigation ruled out a mid-call
  5G handoff.

`prosodyctl check turn` (on the box, as root) is the one-shot health check for
the whole STUN/TURN path: it fetches credentials the way a client would and
performs a real allocation.

## Known limitations

- **No 911.** JMP does not provide emergency services. Emergency calls go
  through the phone's native dialer over the carrier line, which also gives
  proper E911 location and a working callback number. Keep a carrier SIM active.
- **No PSTN call forwarding.** JMP documents forwarding inbound calls to a SIP
  URI only, not to a cell number. If ringing a cell without the app becomes a
  requirement, the answer is an Asterisk box registering *outbound* to a SIP
  provider (no inbound ports needed) — not built.
- **Voice minutes are metered.** JMP includes ~120 min/month; beyond that it is
  roughly $0.0087/min. Texts are unlimited.
- **VoIP number caveats.** Some banks refuse SMS 2FA to numbers flagged as VoIP,
  and VoIP numbers do not get RCS.

## Future work

- **MAM archive backups.** The archive is the reason for self-hosting and
  currently exists only on the VPS. It should be pulled into the B2/local timers
  in `modules/backups.nix` over an outbound connection.
- **acme-dns** to narrow the Cloudflare token's blast radius.
- **`tofu import`** for felix and gaming1, now that the Linode provider exists.
