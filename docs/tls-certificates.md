# TLS certificates

Wildcard TLS certificate management for `*.lan.quietlife.net` using Let's Encrypt, Cloudflare DNS-01 validation, and OpenBao for storage.

## How it works

```
lego/ (ACME client)        OpenBao                  Deploy
───────────────────        ───────                  ──────
Let's Encrypt cert    →  Stored at            →  bao (own listener):
via DNS-01 challenge     kv/infra/certs/          openbao-agent → /var/lib/openbao/tls/
(Cloudflare API)         lan.quietlife.net         + systemctl reload openbao (SIGHUP)

                                                  Traefik (containers):
                                                   openbao-agent → /opt/stacks/certs/
                                                   + docker restart traefik

                                                  Proxmox web UI (pve1):
                                                   make ansible-proxmox
                                                   (proxmox_certs role)
```

bao and containers both run `homelab.openbao-agent` (see `modules/openbao-agent.nix`) with templates that deliver the cert/key from KV to disk and fire a post-rotation hook. Agent polls KV roughly every 1-2 minutes, so a `make lego-store` is automatically picked up without manual deploy. bao talks to its own openbao via loopback with TLS verification disabled — that breaks the chicken-and-egg where bao's listener TLS depends on the very cert the agent is responsible for refreshing.

## Certificate lifecycle

### Renewal (manual)

Certs are renewed using the Dockerized lego CLI in the `lego/` directory:

```bash
cd lego
make lego-renew          # get production cert (use sparingly — rate limits)
make lego-renew-staging  # get staging cert for testing
make lego-store          # push local certs to OpenBao
make lego-retrieve       # pull certs from OpenBao to local files
make lego-show           # display certificate details
make lego-fetch-creds    # test OpenBao credential retrieval
```

Cloudflare API credentials (API token, zone ID) are fetched from OpenBao at deploy time. The API token needs `Zone:DNS:Edit` and `Zone:Zone:Read` permissions.

### Deployment

After `make lego-store` writes the new cert to `kv/infra/certs/lan.quietlife.net`, deployment to consumers happens automatically except for Proxmox:

- **bao** (its own TCP listener): `homelab.openbao-agent` template renders the cert/key from KV to `/var/lib/openbao/tls/{tls.crt,tls.key}` (owned `openbao:openbao`) and fires `systemctl reload openbao` — SIGHUP makes openbao re-read TLS in place without re-sealing. Picked up within ~2 minutes of `lego-store`.
- **Traefik** (containers): same agent pattern, renders to `/opt/stacks/certs/lan.quietlife.net.{crt,key}` (owned `deploy:users`) and fires `docker restart traefik` (~1-2s blip on rotation).
- **Proxmox** (pve1): `make ansible-proxmox` — still Ansible-driven for the Proxmox web UI cert via the `proxmox_certs` role.

### Renewal when the cert is already expired

If the cert has already expired, OpenBao (which serves its own TLS on port
8200) has the expired cert too, and *everything that verifies TLS against bao
starts failing with misleading errors* (see below). Every step that touches
bao needs `BAO_SKIP_VERIFY=true` — including `lego-renew`, which fetches the
Cloudflare credentials from bao before it ever talks to Let's Encrypt.

```bash
# 1. Renew cert from Let's Encrypt. Needs the skip flag: the Cloudflare
#    creds come from bao, whose cert the workstation can't validate.
BAO_SKIP_VERIFY=true make lego-renew

# 2. Push the new cert to OpenBao, same flag, same reason.
BAO_SKIP_VERIFY=true make lego-store

# 3. bao and containers SHOULD auto-rotate within ~5 minutes: bao's
#    openbao-agent connects via loopback with TLS verification disabled
#    (intentional — see modules/openbao-agent.nix), renders the new cert
#    and reloads openbao; containers' agent (which does verify TLS)
#    errors in a retry loop until bao's listener heals, then rotates
#    Traefik. VERIFY IT ACTUALLY HAPPENED:
echo | openssl s_client -connect bao.lan.quietlife.net:8200 2>/dev/null | openssl x509 -noout -enddate
echo | openssl s_client -connect chat.lan.quietlife.net:443 2>/dev/null | openssl x509 -noout -enddate

# 3b. If bao still serves the old cert after ~10 minutes, its agent has
#     wedged on the changed-but-never-re-read KV secret (happened
#     2026-07-28: healthy agent, silent template engine). Restarting the
#     agent is safe — auth is a CIDR-bound AppRole, no secret_id — and
#     unsticks it immediately; containers then heals on its own:
#     ssh bao 'sudo systemctl restart openbao-agent'

# 4. Push the new cert to the Proxmox web UI (still Ansible-managed).
make ansible-proxmox
```

### What an expired cert looks like from the workstation

None of these mention certificates, which cost real debugging time on
2026-07-28. If several appear at once, check the cert dates first:

- `make <anything>` → `ERROR: OpenBao unreachable at https://bao...:8200` —
  the `bao-preflight` guard can't distinguish a TLS refusal from a down
  server.
- `make lego-renew` → `ERROR: Failed to retrieve Cloudflare credentials from
  OpenBao / Ensure BAO_TOKEN is set...` — the creds curl fails TLS quietly
  and the Makefile blames the token.
- containers' `openbao-agent` journal fills with
  `tls: failed to verify certificate: x509: certificate has expired`.

`BAO_SKIP_VERIFY=true make bao-token-status` cuts through all of it: if it
reports a valid token, bao is up and the only problem is the cert.

### OpenBao storage

Certs are stored at `kv/infra/certs/lan.quietlife.net` with keys for the certificate chain, private key, and metadata.

## Related docs

- [docs/openbao.md](openbao.md) — OpenBao operations and TLS management
- [docs/openbao-secrets.md](openbao-secrets.md) — KV secrets structure including cert paths
