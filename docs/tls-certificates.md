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

bao and containers both run `homelab.openbao-agent` (see `modules/openbao-agent.nix`) with templates that deliver the cert/key from KV to disk and fire a post-rotation hook. Agent normally refreshes static KV secrets within roughly five minutes, but propagation must be verified (see the July outage below). bao talks to its own openbao via loopback with TLS verification disabled — that breaks the chicken-and-egg where bao's listener TLS depends on the very cert the agent is responsible for refreshing.

## Certificate lifecycle

### Automated renewal and live checks

`modules/wildcard-certificate` implements #243 and #281. After the policy
setup and deployment below:

- **containers: `wildcard-renewal.timer`**, daily at 04:00 Central, with up
  to 15 minutes of jitter. Reads the current certificate from OpenBao; within
  30 days of expiry, runs the pinned `lego/docker-compose.yml` image with
  Cloudflare DNS-01 and stores the result back in the same KV secret.
- **bao: `wildcard-monitor.timer`**, daily at 06:00 Central, independently
  probes `bao.lan.quietlife.net:8200` and `chat.lan.quietlife.net:443`. It
  verifies TLS trust, hostname and validity, without any OpenBao credentials.
  Renewal and monitoring run on different hosts, so a containers outage
  doesn't also remove the monitor.

Renewal verifies the new certificate's chain, names and matching private key
before storing it. The KV write uses check-and-set against the version read
at startup, preventing a concurrent manual renewal from being overwritten.
It then waits up to 15 minutes for **both live listeners to serve that exact
certificate**, comparing SHA-256 leaf fingerprints. This also runs on days
when issuance isn't needed, so a previous propagation failure is retried.

Successful runs produce journal entries only. Renewal/storage/propagation
failures use the existing `notify-failure@` ntfy hook. The independent
monitor sends one alert per endpoint/certificate at each 21/7/2-day tier
(default/high/urgent). Failed TLS probes produce an urgent alert, deduplicated
until the condition changes or recovers. Undelivered alerts remain pending
for the next run; notification errors also fail the unit. Healthy probes
clear the deduplication state without a recovery notification.

This does not detect failure of the entire LAN or the monitor host itself.
It does catch a stopped renewal timer through the live certificate's age.
No new automatic remediation restarts are performed: existing agent hooks
still reload OpenBao/restart Traefik when their files rotate, and stalled
propagation raises an alert for operator investigation. Proxmox's web UI
certificate remains a manual `make ansible-proxmox` deployment.

#### One-time setup and deployment

Run these deliberately when ready to enable production renewal. Nothing
here needs a new static token or copied ACME private key.

1. Using an existing privileged Bao session, install the narrowly scoped
   policy from the repo root:

   ```bash
   bao policy write wildcard-renewal openbao/policies/wildcard-renewal.hcl
   ```

   It grants read access to `kv/data/infra/cloudflare` and read/update access
   to only `kv/data/infra/certs/lan.quietlife.net`. The certificate secret
   must already exist. The existing Cloudflare token must retain both
   `Zone:DNS:Edit` and `Zone:Zone:Read` for the relevant zone.

2. Attach it to the **containers** host's existing AppRole (still named
   `containers2`). This helper preserves its other attached policies:

   ```bash
   make openbao-approle-create-role NAME=containers2 IP=10.10.15.11 EXTRA_POLICIES=wildcard-renewal
   ```

3. Deploy the reviewed host configurations:

   ```bash
   make nix-deploy-host HOST=containers
   make nix-deploy-host HOST=bao
   ```

   The containers deployment changes the agent config, restarting the agent
   so it authenticates with the newly attached policy and renders the
   Cloudflare token. The timers are enabled by deployment and may catch up
   immediately. Inspect the normal deployment preview before confirming.

4. Check timers/journals on the respective hosts. To deliberately exercise
   the jobs immediately (renewal can issue a real certificate and trigger
   the existing consumer rotation hooks):

   ```bash
   ssh -i ansible/keys/deploy deploy@containers sudo -n systemctl start wildcard-renewal.service
   ssh -i ansible/keys/deploy deploy@containers journalctl -u wildcard-renewal -n 20 --no-pager
   ssh -i ansible/keys/deploy deploy@bao sudo -n systemctl start wildcard-monitor.service
   ssh -i ansible/keys/deploy deploy@bao journalctl -u wildcard-monitor -n 20 --no-pager
   ```

Renewal state lives in `/var/lib/wildcard-renewal/certs` on containers,
root-only: the lego account, certificate and key survive runs/reboots. On
first use, the job waits until the certificate already in Bao is due before
registering an account and issuing a certificate. Do not copy workstation
staging files into this directory. After a successful issuance but failed
upload, the next run reuses the local certificate instead of reissuing.
Losing this local state doesn't invalidate the certificate in Bao; a new
account/certificate can be obtained when renewal is next due.

Cloudflare's token is rendered to a root-only file and mounted read-only
into lego. The Bao token comes from the agent's runtime sink on each API
request. Neither secret is in the Nix store, command arguments or Docker
environment values. Subprocess output and HTTP response bodies are withheld
from journals, since failure journals are forwarded to ntfy.

Missing credentials fail and alert rather than silently skipping. A 403
after setup suggests the agent hasn't authenticated with the new policy.
On a propagation alert, use the live-listener checks below and investigate
the corresponding agent/reload hook; don't assume another issuance will
help. A timed-out lego invocation can leave a container named
`wildcard-renewal-lego`; its fixed name prevents overlapping retries. Inspect
it before manually stopping/removing it and retrying the job.

#### Local validation

`make nix-check` runs Ruff, mypy and offline certificate-job tests before
building all four host configurations. Tests cover issuance failure,
publication retries, CAS writes, stale/unreachable listeners, alert escalation
and deduplication. They never issue certificates or contact production.
The first real renewal and observed propagation remain deployment checks.

### Manual renewal / recovery

Certs are renewed using the Dockerized lego CLI in the `lego/` directory:

```bash
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
