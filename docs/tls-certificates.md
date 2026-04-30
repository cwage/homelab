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

If the cert has already expired, OpenBao (which serves its own TLS on port 8200) will also have the expired cert and the workstation can't trust it for `make lego-store`. The recovery is short:

```bash
# 1. Renew cert from Let's Encrypt (doesn't talk to OpenBao).
make lego-renew

# 2. Push the new cert to OpenBao with TLS verification disabled. The
#    workstation can't validate bao's expired cert, so verify-skip is
#    needed for this one push.
BAO_SKIP_VERIFY=true make lego-store

# 3. bao and containers auto-rotate within ~2 minutes — no further
#    action needed. bao's openbao-agent connects via loopback with TLS
#    verification disabled (intentional, see modules/openbao-agent.nix
#    and hosts/openbao/configuration.nix), so an expired listener cert
#    doesn't block the agent from refreshing it.

# 4. Push the new cert to the Proxmox web UI (still Ansible-managed).
make ansible-proxmox
```

### OpenBao storage

Certs are stored at `kv/infra/certs/lan.quietlife.net` with keys for the certificate chain, private key, and metadata.

## Related docs

- [docs/openbao.md](openbao.md) — OpenBao operations and TLS management
- [docs/openbao-secrets.md](openbao-secrets.md) — KV secrets structure including cert paths
