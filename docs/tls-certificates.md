# TLS certificates

Wildcard TLS certificate management for `*.lan.quietlife.net` using Let's Encrypt, Cloudflare DNS-01 validation, and OpenBao for storage.

## How it works

```
lego/ (ACME client)           OpenBao                    Ansible
───────────────────           ───────                    ───────
Let's Encrypt cert    →  Stored at                 →  Retrieved at deploy time
via DNS-01 challenge     kv/infra/certs/               and deployed to:
(Cloudflare API)         lan.quietlife.net              - Traefik (/opt/stacks/certs/)
                                                        - Proxmox (pveproxy)
```

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

The cert is retrieved from OpenBao and deployed to services:

- **Traefik** (containers2): the cert and key currently live as mutable files in `/opt/stacks/certs/` (placed imperatively after the NixOS migration; slated to move to a NixOS-driven lego workflow). Traefik picks them up via the `traefik-tls.yml` file provider.
- **Proxmox** (pve1): `make ansible-proxmox` deploys cert via the `proxmox_certs` role for the Proxmox web UI

**Note:** Traefik does not automatically reload bind-mounted cert files. After replacing them, restart the container: `ssh containers2 'docker restart traefik'`.

### Renewal when the cert is already expired

If the cert has already expired, OpenBao (which serves its own TLS on port 8200) will also have the expired cert. Both `make lego-store` (curl to OpenBao) and Ansible's OpenBao lookups will fail with `SSL: CERTIFICATE_VERIFY_FAILED`. To break the chicken-and-egg cycle:

```bash
# 1. Renew cert from Let's Encrypt (this doesn't talk to OpenBao)
make lego-renew

# 2. Store in OpenBao with TLS verification disabled
BAO_SKIP_VERIFY=true make lego-store

# 3. Copy the renewed cert/key onto containers2 and restart Traefik
#    (containers2 will pick this up automatically once cert delivery is
#    moved into openbao-agent / a NixOS lego module — until then it's manual)
scp lego/certs/_.lan.quietlife.net.crt containers2:/opt/stacks/certs/lan.quietlife.net.crt
scp lego/certs/_.lan.quietlife.net.key containers2:/opt/stacks/certs/lan.quietlife.net.key
ssh containers2 'docker restart traefik'

# 4. Update OpenBao's own TLS cert (it listens on :8200 with its own cert)
#    The bao2 NixOS host has the cert staged manually under /var/lib/openbao/tls/
#    until the cert auto-renewal module lands (issue #220).

# 5. Subsequent runs (proxmox, etc.) should work normally now
make ansible-proxmox
```

### OpenBao storage

Certs are stored at `kv/infra/certs/lan.quietlife.net` with keys for the certificate chain, private key, and metadata.

## Related docs

- [docs/openbao.md](openbao.md) — OpenBao operations and TLS management
- [docs/openbao-secrets.md](openbao-secrets.md) — KV secrets structure including cert paths
