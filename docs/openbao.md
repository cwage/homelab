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
- `/etc/openbao/backup-token` - Snapshot-backup token, staged manually

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

1. `make lego-renew && make lego-store` — get a fresh cert into KV.
2. On `bao`: `sudo systemctl restart openbao-agent` to force an immediate re-render,
   or wait for the next poll cycle.
3. Verify the new cert is live:
   ```bash
   openssl s_client -connect bao.lan.quietlife.net:8200 -showcerts </dev/null \
     | openssl x509 -noout -dates
   ```
4. If clients still see the old cert, `sudo systemctl reload openbao` on `bao` to SIGHUP
   the listener. Do **not** use `restart` — it leaves OpenBao sealed.

## Backup Token Setup (One-Time)

The backup system requires a dedicated token with minimal permissions. After initial setup:

```bash
ssh deploy@10.10.15.16

# Use the hostname (preferred, as 127.0.0.1 is not included as a SAN in either certificate).
# If hostname resolution does not work, you may use 127.0.0.1 with BAO_SKIP_VERIFY=true:
#   export BAO_SKIP_VERIFY=true
#   export BAO_ADDR="https://127.0.0.1:8200"
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login
# Enter root token

# Enable KV secrets engine (if not already done)
bao secrets enable -path=kv kv-v2

# Create backup policy with minimal permissions
bao policy write backup - <<EOF
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOF

# Create long-lived backup token
bao token create -policy=backup -no-default-policy -orphan -period=8760h -display-name="backup-automation"
# Save the token!

# Store token in KV for future Ansible retrieval (issue #67)
bao kv put kv/backup/openbao token="<token-from-above>"

# Create the token file for the backup script
sudo tee /etc/openbao/backup-token > /dev/null <<EOF
<token-from-above>
EOF
sudo chmod 600 /etc/openbao/backup-token
sudo chown root:root /etc/openbao/backup-token
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

### Troubleshooting: Backup Token Expired

The backup token is periodic (`-period=8760h`). However, OpenBao's system-level
`max_lease_ttl` (default: 32 days) caps the effective period. If the token is not
renewed within that window — or if OpenBao is sealed long enough — the token expires
and backups fail with `permission denied`. To recreate:

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login  # root token from Bitwarden

bao token create -policy=backup -no-default-policy -orphan -period=8760h -display-name="backup-automation"

sudo tee /etc/openbao/backup-token > /dev/null <<EOF
<new-token>
EOF
sudo chmod 600 /etc/openbao/backup-token
sudo chown root:root /etc/openbao/backup-token

# Verify
sudo systemctl start openbao-backup.service
journalctl -u openbao-backup.service --no-pager -n 20
```

To prevent future expiry, consider increasing `max_lease_ttl` in the server config
or on the `token/` auth mount to match the intended period.

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
```

### Creating Workstation Tokens

Once the policy exists, see the
[Workstation Bootstrap](openbao-secrets.md#workstation-bootstrap) section in
`openbao-secrets.md` to generate a token for a new machine or replace an expired one.

## Related

- Issue #62 - Original implementation plan
- Issue #63 - Let's Encrypt automation (blocked by OpenBao for Cloudflare token storage)
