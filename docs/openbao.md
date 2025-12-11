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

export BAO_ADDR="https://127.0.0.1:8200"
export BAO_SKIP_VERIFY=true

bao operator unseal
# Paste unseal key from Bitwarden
```

## CLI Usage from Workstation

To interact with OpenBao from your local machine:

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"

# Copy the server's self-signed cert for verification
scp deploy@10.10.15.11:/opt/openbao/tls/tls.crt ~/.config/openbao-ca.crt
export BAO_CACERT=~/.config/openbao-ca.crt

bao login
# Paste root token (or other token)

bao status
bao secrets list
```

> **Security Note:** Avoid using `BAO_SKIP_VERIFY=true` for routine access as it disables
> TLS certificate verification, allowing potential man-in-the-middle attacks. Only use
> it for initial setup when you cannot yet copy the certificate. For regular use, always
> configure `BAO_CACERT` with the server's certificate.

## Configuration

Key files on the server:
- `/etc/openbao/openbao.hcl` - Server configuration
- `/opt/openbao/tls/tls.crt` - TLS certificate
- `/opt/openbao/tls/tls.key` - TLS private key
- `/opt/openbao/data/` - Raft data directory

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

## Related

- Issue #62 - Original implementation plan
- Issue #63 - Let's Encrypt automation (blocked by OpenBao for Cloudflare token storage)
