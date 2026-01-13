# OpenBao Secrets Management

OpenBao is deployed as a dedicated VM for centralized secrets management.

## Infrastructure

- **VM**: `openbao` (VM ID 103)
- **IP**: 10.10.15.11
- **DNS**: `bao.lan.quietlife.net`
- **Port**: 8200 (HTTPS)
- **Storage**: Integrated Raft at `/opt/openbao/data`

## Deployment

```bash
# 1. Provision the VM
make tofu-plan
make tofu-apply

# 2. Wait for VM to boot (~1-2 min), then verify connectivity
make ansible-ping LIMIT=openbao

# 3. Deploy DNS record (optional, if not already done)
make ansible-dns

# 4. Install and configure OpenBao
make ansible-openbao
```

## Initial Setup (One-Time)

After first deployment, SSH in to initialize OpenBao:

```bash
ssh deploy@10.10.15.11

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
ssh deploy@10.10.15.11

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

Once the wildcard certificate is deployed (see TLS Certificate Management below), standard
TLS verification works automatically - no `BAO_CACERT` or `BAO_SKIP_VERIFY` needed.

### Before Wildcard Certificate is Deployed

During initial setup (self-signed cert), either:

```bash
# Option 1: Skip verification (bootstrap only)
export BAO_SKIP_VERIFY=true

# Option 2: Copy self-signed cert to trust store
scp deploy@10.10.15.11:/opt/openbao/tls/tls.crt ~/.config/openbao-ca.crt
export BAO_CACERT=~/.config/openbao-ca.crt
```

> **Security Note:** Avoid using `BAO_SKIP_VERIFY=true` for routine access as it disables
> TLS certificate verification, allowing potential man-in-the-middle attacks. Once the
> wildcard certificate is deployed, remove `BAO_SKIP_VERIFY` from your environment.

## Configuration

Key files on the server:
- `/etc/openbao/openbao.hcl` - Server configuration
- `/opt/openbao/tls/tls.crt` - TLS certificate
- `/opt/openbao/tls/tls.key` - TLS private key
- `/opt/openbao/data/` - Raft data directory

## TLS Certificate Management

OpenBao's TLS certificate has a two-stage lifecycle:

### Stage 1: Self-Signed (Bootstrap)

On initial deployment, the Ansible role generates a self-signed certificate. This allows
OpenBao to start with TLS enabled, but clients must use `BAO_SKIP_VERIFY=true` or copy
the self-signed cert to their trust store.

### Stage 2: Wildcard Certificate (Production)

Once the Let's Encrypt wildcard certificate is stored in OpenBao (via `make lego-store`),
subsequent runs of `make ansible-openbao` will:

1. Check if OpenBao is unsealed
2. Fetch the wildcard cert from `kv/infra/certs/lan.quietlife.net`
3. Deploy it to `/opt/openbao/tls/`
4. Restart OpenBao if the certificate changed

After this, clients can connect with standard TLS verification (no `BAO_SKIP_VERIFY`).

### The Bootstrap Problem

There's an inherent chicken-and-egg issue: to deploy the certificate TO OpenBao, we must
connect to OpenBao, but we can't verify its certificate before we deploy it.

**Solution**: The Ansible role always uses `validate_certs: false` when fetching the
certificate for OpenBao itself. This is acceptable because:
- It's a controlled operation (Ansible → localhost OpenBao)
- It's only for deploying OpenBao's own certificate
- Other services can and should use `validate_certs: true`

### Recovery from Expired Certificate

If the wildcard certificate expires:

1. Set `BAO_SKIP_VERIFY=true` in your environment
2. Renew the certificate: `make lego-renew`
3. Store to OpenBao: `make lego-store`
4. Redeploy to OpenBao: `make ansible-openbao`
5. Remove `BAO_SKIP_VERIFY` from your environment

### Disabling Wildcard Cert Deployment

To skip wildcard certificate deployment (use self-signed only):

```yaml
# In host_vars/openbao.yml or via extra vars
openbao_deploy_wildcard_cert: false
```

## Backup Token Setup (One-Time)

The backup system requires a dedicated token with minimal permissions. After initial setup:

```bash
ssh deploy@10.10.15.11

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

## Backups

Automated daily Raft snapshots are stored on NFS:
- **NFS Share**: `10.10.15.4:/volume1/homelab-backups`
- **Mount Point**: `/mnt/backups`
- **Backup Directory**: `/mnt/backups/vm/openbao`
- **Retention**: 30 days
- **Schedule**: Daily (with up to 1 hour random delay)

The backup is managed by a systemd timer:

```bash
# Check timer status
systemctl status openbao-backup.timer

# View next scheduled run
systemctl list-timers openbao-backup.timer

# Manually trigger a backup
systemctl start openbao-backup.service

# View backup logs
journalctl -u openbao-backup.service
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

## Ansible Deploy Token Setup

Ansible uses a dedicated token to fetch secrets during playbook runs (e.g., gaming server passwords).

### Initial Setup (One-Time)

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
EOF

# Create token (30-day TTL)
bao token create -policy=ansible-deploy -ttl=720h -display-name="ansible-deploy"
# Save the token to ansible/.env as BAO_TOKEN
```

### Token Renewal

The ansible-deploy token expires after 30 days. To renew:

```bash
# Authenticate with root token
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login
# Enter root token

# Create new token
bao token create -policy=ansible-deploy -ttl=720h -display-name="ansible-deploy"

# Update ansible/.env with new BAO_TOKEN value
```

Old tokens expire naturally - no cleanup needed.

## Related

- Issue #62 - Original implementation plan
- Issue #63 - Let's Encrypt automation (blocked by OpenBao for Cloudflare token storage)
