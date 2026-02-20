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

Ansible retrieves the cert from OpenBao and deploys it to services:

- **Traefik** (containers host): `make ansible-containers` deploys cert to `/opt/stacks/certs/` and configures `traefik-tls.yml` file provider
- **Proxmox** (pve1): `make ansible-proxmox` deploys cert via the `proxmox_certs` role for the Proxmox web UI

### OpenBao storage

Certs are stored at `kv/infra/certs/lan.quietlife.net` with keys for the certificate chain, private key, and metadata.

## Related docs

- [docs/openbao.md](openbao.md) — OpenBao operations and TLS management
- [docs/openbao-secrets.md](openbao-secrets.md) — KV secrets structure including cert paths
