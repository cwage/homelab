# OpenBao Secrets Management

OpenBao is deployed as a dedicated VM for centralized secrets management.

## Infrastructure

- **VM**: `bao` (VM ID 151, NixOS — declared in `tofu/bao.tf` and `hosts/openbao/configuration.nix`)
- **IP**: 10.10.15.16
- **DNS**: `bao.lan.quietlife.net`
- **Port**: 8200 (HTTPS)
- **Storage**: Integrated Raft at `/var/lib/openbao/data`

## Deployment

```bash
# 1. Provision the VM
make tofu-plan
make tofu-apply

# 2. Wait for VM to boot (~1-2 min), then verify connectivity
ping -c1 bao.lan.quietlife.net

# 3. Add DNS record if needed (edit hosts/dns1/configuration.nix, then deploy)
make nix-deploy-host HOST=dns1 TARGET=10.10.15.15

# 4. Deploy the NixOS configuration
make nix-deploy-host HOST=bao TARGET=10.10.15.16
```

## Initial Setup (One-Time)

After first deployment, SSH in to initialize OpenBao:

```bash
ssh deploy@10.10.15.16

# Set environment
export BAO_ADDR="https://127.0.0.1:8200"
export BAO_SKIP_VERIFY=true

# Initialize with single unseal key
bao operator init -key-shares=1 -key-threshold=1
```

This outputs:
- **Unseal Key** - Store in Bitwarden immediately
- **Root Token** - Store in Bitwarden immediately

Then unseal:

```bash
bao operator unseal
# Paste unseal key when prompted
```

## After Reboot

OpenBao starts sealed after every restart. To unseal:

```bash
ssh deploy@10.10.15.16

# Use the hostname for proper TLS verification
export BAO_ADDR="https://bao.lan.quietlife.net:8200"

bao operator unseal
# Paste unseal key from Bitwarden
```

## CLI Usage from Workstation

To interact with OpenBao from your local machine:

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
export BAO_TOKEN="<your-token>"

bao status
bao secrets list
```

openbao-agent on `bao` renders the LE `*.lan.quietlife.net` wildcard cert directly into
the server's TLS paths (see TLS Certificate Management below), so standard verification
works out of the box — no `BAO_CACERT` or `BAO_SKIP_VERIFY` needed for normal client use.

### Before openbao-agent Has Rendered a Cert (Fresh-VM Bootstrap)

On a fresh VM, `openbao.service` will not start until `/var/lib/openbao/tls/{tls.crt,tls.key}`
exist (see `ConditionPathExists` in the unit). The first-boot procedure is to stage a
self-signed cert by hand, unseal the server, then let openbao-agent overwrite those files
with the real wildcard cert on its next render. During that staging window, clients need:

```bash
export BAO_SKIP_VERIFY=true
```

> **Security Note:** `BAO_SKIP_VERIFY=true` disables TLS verification and is for the
> bootstrap window only. Once openbao-agent has rendered the wildcard cert, unset it.

## Configuration

Key files on the server (declared by `hosts/openbao/configuration.nix`):
- `/etc/openbao-server/openbao.hcl` - Server configuration. The `/etc/openbao/` directory itself is 0750 root:root (managed by the `openbao-agent` module), so the server config lives one directory over to remain readable by the `openbao` user.
- `/var/lib/openbao/tls/tls.crt` - TLS certificate (rendered by openbao-agent from KV)
- `/var/lib/openbao/tls/tls.key` - TLS private key (rendered by openbao-agent from KV)
- `/var/lib/openbao/data/` - Raft data directory
- `/run/openbao-agent/token` - openbao-agent's auto-auth token; the daily Raft snapshot job authenticates with it

## TLS Certificate Management

OpenBao's listener uses the Let's Encrypt wildcard cert for `*.lan.quietlife.net`. On the
NixOS `bao` VM, the cert is delivered by the local `openbao-agent` service (declared in
`hosts/openbao/configuration.nix`), which polls KV at `kv/data/infra/certs/lan.quietlife.net`
and renders the `certificate` and `private_key` fields to `/var/lib/openbao/tls/`. After the
key file is re-rendered, the agent runs `systemctl reload openbao`, which SIGHUPs the
server. SIGHUP re-reads the TLS files in place without re-sealing — a full restart would
leave OpenBao sealed and require manual unseal.

### Renewal

When the cert is approaching expiry:

```bash
make lego-renew    # request a fresh cert via DNS-01 against Cloudflare
make lego-store    # publish it to kv/infra/certs/lan.quietlife.net
```

That's it — openbao-agent picks up the new KV version on its next render and SIGHUPs the
server.

### Bootstrap Chicken-and-Egg

The agent talks to bao's own listener to read KV — but that listener uses the very cert
the agent is responsible for refreshing. To break the cycle, the agent connects via
`https://localhost:8200` with `tls_skip_verify = true`. This is safe because the
connection is loopback-only (no MITM surface) and means an expired cert can still be
swapped out.

A consequence: `openbao.service` has `ConditionPathExists` on `tls.crt` and `tls.key`, so
on a fresh VM the cert files must be staged out-of-band before the server will start.
Once it's running, the agent keeps them current.

### Recovery from Expired Certificate

If the cert expired in place (i.e., openbao-agent stopped renewing for some reason):

1. Get a fresh cert into KV. Both lego targets talk to OpenBao (lego-renew fetches the
   Cloudflare credentials, lego-store posts the renewed cert back) and TLS verification
   against bao's now-expired listener will fail — set `BAO_SKIP_VERIFY=true` so the
   wrapped curl calls pass `--insecure`:
   ```bash
   export BAO_SKIP_VERIFY=true
   make lego-renew
   make lego-store
   unset BAO_SKIP_VERIFY
   ```
2. On `bao`: `sudo systemctl restart openbao-agent` to force an immediate re-render,
   or wait for the next poll cycle.
3. Verify the new cert is live:
   ```bash
   openssl s_client -connect bao.lan.quietlife.net:8200 -showcerts </dev/null \
     | openssl x509 -noout -dates
   ```
4. If clients still see the old cert, `sudo systemctl reload openbao` on `bao` to SIGHUP
   the listener. Do **not** use `restart` — it leaves OpenBao sealed.

## Token Inventory

When something starts failing with `403 permission denied`, use this table to work out
*which* token died and where its runbook is. The two periodic tokens
(`-period=8760h`) are never renewed by anything, so each one expires **one year after
it was minted**. Production hosts (`containers2`, and `bao` itself) authenticate
through `openbao-agent` with AppRole and do not use any of these — that includes the
daily Raft snapshot on `bao`, which runs on the agent's token (see
[Backups](#backups)) and has nothing to rotate.

| Token | Policy | Lives at | Used by | When it expires you see | Runbook |
|-------|--------|----------|---------|-------------------------|---------|
| root | — | Bitwarden | you, to mint everything below | never expires | [Initial Setup](#initial-setup-one-time) |
| `backup-remote` | `backup-remote` | `kv/backup/remote-token` | the `backup/` tool **from a workstation** only; the production schedule on `containers2` uses AppRole | `make backup-*` fails with 403 on the workstation, production keeps running | [backup/README.md](../backup/README.md#token-rotation-workstation) |
| `approle-admin` | `approle-admin` | `kv/infra/openbao/admin-token` | `make openbao-approle-*` | those targets fail with 403 | [The approle-admin Token](#the-approle-admin-token-reminting) |
| workstation (30-day TTL, not periodic) | `ansible-deploy` + `calibre-readers` | `BAO_TOKEN` in your `.env` | `make tofu-*` / `make ansible-*` | the `bin/bao-token-status` preflight reports the token expired or invalid | [Workstation Bootstrap](openbao-secrets.md#workstation-bootstrap) |

## Backup Policy Setup (One-Time)

The daily Raft snapshot (`openbao-backup.service` on `bao`, see [Backups](#backups))
authenticates with the token that `openbao-agent` on `bao` already holds from its
AppRole login (`/run/openbao-agent/token`). The agent keeps that token renewed, so
there is no long-lived credential to stage or rotate. All the job needs is a policy
that can do exactly one thing — read `sys/storage/raft/snapshot` — attached to
`bao`'s AppRole role.

**1. Create the policy** (once, as root on `bao`):

```bash
ssh deploy@10.10.15.16

# Use the hostname (127.0.0.1 is not a SAN in the certificate). If DNS is down you
# can instead use BAO_ADDR="https://127.0.0.1:8200" with BAO_SKIP_VERIFY=true.
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login
# Enter root token (Bitwarden)

bao policy write backup - <<EOF
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOF
```

**2. Attach it to `bao`'s AppRole role** from the workstation. The create-role target is
an upsert that preserves existing policies but **replaces the CIDR binding wholesale**,
so `EXTRA_CIDRS=127.0.0.1/32` is mandatory here: `bao`'s agent talks to its own server
over loopback and would lock itself out without it. The role is still named `bao2` in
OpenBao (kept for role_id stability across the VM migration, like `containers2`);
confirm with the list target if in doubt.

```bash
make openbao-approle-list
make openbao-approle-create-role NAME=bao2 IP=10.10.15.16 EXTRA_CIDRS=127.0.0.1/32 EXTRA_POLICIES=backup
```

Check the output: `bound_cidrs` must list both `10.10.15.16/32` and `127.0.0.1/32`,
and `token_policies` must include `backup` and `nixos-host`.

**3. Make the agent log in again.** A token's policies are fixed when it is issued and
renewal does not change them, so the running agent keeps its old token until it
re-authenticates. Restarting the agent is safe: it re-renders its templates only if
their content changed and never restarts `openbao.service` itself.

```bash
sudo systemctl restart openbao-agent.service
sudo sh -c 'BAO_TOKEN=$(cat /run/openbao-agent/token) BAO_ADDR=https://127.0.0.1:8200 BAO_SKIP_VERIFY=true /run/current-system/sw/bin/bao token lookup -format=json' | jq -r '.data.policies'
```

The policies list must include `backup`. Then run the job once to prove it:

```bash
sudo systemctl start openbao-backup.service
journalctl -u openbao-backup.service --no-pager -n 10
```

## Backup-Remote Token Setup (One-Time)

The NAS-to-Backblaze B2 backup system uses a separate token scoped to only the B2 and rclone-crypt KV paths. This token is deployed to the containers host via Ansible and used by the backup container at runtime to fetch credentials.

```bash
# Create the backup-remote policy
bao policy write backup-remote - <<'EOF'
path "kv/data/backup/backblaze" {
  capabilities = ["read"]
}
path "kv/data/backup/rclone-crypt" {
  capabilities = ["read"]
}
EOF

# Create periodic token with that policy
bao token create \
  -policy=backup-remote \
  -no-default-policy \
  -orphan \
  -period=8760h \
  -display-name="backup-remote"

# Store the token for Ansible retrieval
bao kv put kv/backup/remote-token token="<token-from-above>"
```

See [`backup/README.md`](../backup/README.md) for full setup procedures, token rotation, and troubleshooting.

## Backups

Automated daily Raft snapshots are stored on NFS:
- **NFS Share**: `10.10.15.4:/volume1/homelab-backups`
- **Mount Point**: `/mnt/backups`
- **Backup Directory**: `/mnt/backups/vm/openbao`
- **Retention**: 30 days
- **Schedule**: Daily at 00:30 (server local time) via systemd timer
- **Auth**: `openbao-agent`'s AppRole token at `/run/openbao-agent/token`, carrying the
  `backup` policy (see [Backup Policy Setup](#backup-policy-setup-one-time)). The agent
  renews it, so there is nothing to rotate.

```bash
# Check timer status
systemctl status openbao-backup.timer
systemctl list-timers openbao-backup.timer

# Manually trigger a backup
sudo systemctl start openbao-backup.service

# View backup logs
journalctl -u openbao-backup.service --no-pager -n 20
```

Manual snapshots can also be taken:

```bash
bao operator raft snapshot save /mnt/backups/vm/openbao/manual-$(date +%Y%m%d).snap
```

To restore from a snapshot:

```bash
bao operator raft snapshot restore /mnt/backups/vm/openbao/openbao-YYYYMMDD-HHMMSS.snap
```

The VM is also backed up via Proxmox VM backups.

### Troubleshooting: Snapshot Fails With 403

Symptom — a ❌ "Job failed on bao: openbao-backup.service" notification whose journal
tail shows:

```
Error taking the snapshot: Error making API request.
URL: GET 127.0.0.1:8200/v1/sys/storage/raft/snapshot
Code: 403. Errors:
* permission denied
```

The job authenticates with `openbao-agent`'s token, so a 403 means that token does not
carry the `backup` policy. Nothing else in the homelab uses that policy, so nothing else
breaks — but there are no new Raft snapshots until it is fixed. In order of likelihood:

1. **`bao`'s AppRole role lost the policy** (the role was recreated, or the policy was
   deleted). Check on `bao`:

   ```bash
   sudo sh -c 'BAO_TOKEN=$(cat /run/openbao-agent/token) BAO_ADDR=https://127.0.0.1:8200 BAO_SKIP_VERIFY=true /run/current-system/sw/bin/bao token lookup -format=json' | jq -r '.data.policies'
   ```

   If `backup` is missing, redo steps 2 and 3 of
   [Backup Policy Setup](#backup-policy-setup-one-time). Remember `EXTRA_CIDRS=127.0.0.1/32`.
2. **The policy was attached but the agent never logged in again**, so its token predates
   the change. Step 3 of the same section (restart the agent, verify, run the job).

A different failure — `openbao-agent token sink missing or empty` — means the agent is
not running or has not authenticated: `systemctl status openbao-agent.service` and
`journalctl -u openbao-agent.service -n 30` on `bao`.

**History.** Until September 2026 this job used a dedicated one-year periodic token,
staged by hand at `/etc/openbao/backup-token` with a copy at `kv/backup/openbao`, and it
expired unnoticed once a year. Both are gone. If either still exists (an old snapshot
restore, say), revoke the token by accessor and delete the copies:

```bash
bao token revoke -accessor "$(sudo sh -c 'BAO_TOKEN=$(cat /etc/openbao/backup-token) BAO_ADDR=https://127.0.0.1:8200 BAO_SKIP_VERIFY=true /run/current-system/sw/bin/bao token lookup -format=json' | jq -r .data.accessor)"
sudo rm /etc/openbao/backup-token
bao kv metadata delete -mount=kv backup/openbao
```

## Ansible Deploy Token Setup

Ansible uses a dedicated token to fetch secrets during playbook runs (e.g., gaming server passwords).

### Initial Policy Setup (One-Time)

```bash
# Authenticate with root token
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login
# Enter root token

# Create policy for Ansible deployments
bao policy write ansible-deploy - <<EOF
path "kv/data/services/*" {
  capabilities = ["read"]
}
path "kv/data/infra/*" {
  capabilities = ["read"]
}
path "kv/data/backup/*" {
  capabilities = ["read"]
}
EOF

# Write access to exactly one key: the Calibre-Web reader allowlist
# (docs/calibre.md). Kept out of ansible-deploy so the broad policy stays
# read-only; workstation tokens carry BOTH policies.
bao policy write calibre-readers - <<EOF
path "kv/data/infra/cloudflare/calibre-access" {
  capabilities = ["create", "update", "read"]
}
EOF

# Read access to the RHS specials SMS credentials (the JMP account's
# XMPP creds + recipient number — modules/rhs-specials). Attached to
# the containers host's AppRole, NOT the base nixos-host policy, so the
# plaintext XMPP password is readable only by the one host that sends SMS:
#   make openbao-approle-create-role NAME=containers2 IP=10.10.15.11 EXTRA_POLICIES=rhs-sms
bao policy write rhs-sms - <<EOF
path "kv/data/infra/rhs-sms" {
  capabilities = ["read"]
}
EOF

# Read access to the Renovate GitHub token (fine-grained PAT scoped to the
# homelab repo — modules/renovate.nix). Attached to the containers host's
# AppRole only, since that's the one host that runs Renovate:
#   make openbao-approle-create-role NAME=containers2 IP=10.10.15.11 EXTRA_POLICIES=renovate
bao policy write renovate - <<EOF
path "kv/data/infra/renovate" {
  capabilities = ["read"]
}
EOF
```

### Wildcard Certificate Renewal

The containers AppRole also uses the `wildcard-renewal` policy for automated
LAN TLS renewal. Its source is `openbao/policies/wildcard-renewal.hcl`: read
the Cloudflare credential, read/update the one LAN certificate secret.
See [TLS setup and deployment](tls-certificates.md#one-time-setup-and-deployment)
for policy attachment and agent reauthentication. Do not grant certificate
write access to the shared `nixos-host` policy.

### Creating Workstation Tokens

Once the policies exist, see the
[Workstation Bootstrap](openbao-secrets.md#workstation-bootstrap) section in
`openbao-secrets.md` to generate a token for a new machine or replace an expired one.

### The approle-admin Token (Reminting)

The `make openbao-approle-*` targets fetch a privileged token from
`kv/infra/openbao/admin-token` (field `token`, policy `approle-admin`) to
manage AppRole roles. It is periodic and nothing renews it, so roughly once a
year it expires and the targets start failing with `403 permission denied`.
Remint it on the bao server (`bao login` with the root token) — command
substitution keeps the new token off the screen:

```bash
bao kv put -mount=kv infra/openbao/admin-token token=$(bao token create -policy=approle-admin -no-default-policy -orphan -period=8760h -field=token -display-name=approle-admin)
```

Heads-up when a create-role run fails this way: `setup-approle.sh` merges the
role's *existing* policies client-side, and with a dead token that read
silently returns nothing. Always confirm the rerun prints
`(preserved existing: ...)` with the expected extra policies (e.g.
`backup-remote` on `containers2`) — a write that "succeeds" without them
would strip those attachments.

## Related

- Issue #62 - Original implementation plan
- Issue #63 - Let's Encrypt automation (blocked by OpenBao for Cloudflare token storage)
