# lego — TLS certificate management

Dockerized [lego](https://go-acme.github.io/lego/) ACME client for obtaining and renewing the `*.lan.quietlife.net` wildcard certificate from Let's Encrypt via DNS-01 challenge (Cloudflare API).

For the end-to-end certificate lifecycle (renewal → OpenBao storage → deployment to Traefik/Proxmox), see [docs/tls-certificates.md](../docs/tls-certificates.md).

## Prerequisites

- Root `.env` configured with `BAO_ADDR` and `BAO_TOKEN`
- Cloudflare API credentials stored in OpenBao at `kv/infra/cloudflare` with `api_token` and `zone_id` fields
- The Cloudflare API token needs `Zone:DNS:Edit` and `Zone:Zone:Read` permissions

## Commands

```bash
make renew            # request/renew production cert (use sparingly — rate limits)
make renew-staging    # request staging cert (fake, for testing)
make renew-force      # force renewal even if cert is still valid
make store            # push local certs to OpenBao
make retrieve         # pull certs from OpenBao to local files
make show             # display certificate details (subject, dates, issuer)
make list             # list local certificate files
make fetch-creds      # test OpenBao credential retrieval (masked output)
```

## Typical renewal workflow

```bash
make renew            # get new cert from Let's Encrypt
make store            # push to OpenBao
# Then deploy via Ansible:
#   make ansible-containers   (Traefik)
#   make ansible-proxmox      (Proxmox web UI)
```

## How it works

1. Fetches Cloudflare API token and zone ID from OpenBao
2. Runs lego in a Docker container with DNS-01 challenge via Cloudflare
3. Certs are written locally to `certs/certificates/` (gitignored)
4. `make store` pushes them to OpenBao at `kv/infra/certs/lan.quietlife.net`
5. Ansible retrieves them from OpenBao at deploy time

Uses `--dns.resolvers=1.1.1.1:53` to work around split-horizon DNS (lego can't find the parent zone via the local resolver).
