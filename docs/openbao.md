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
export BAO_CACERT=/path/to/cert.pem  # or use BAO_SKIP_VERIFY=true for self-signed

bao login
# Paste root token (or other token)

bao status
bao secrets list
```

## Configuration

Key files on the server:
- `/etc/openbao/openbao.hcl` - Server configuration
- `/opt/openbao/tls/tls.crt` - TLS certificate
- `/opt/openbao/tls/tls.key` - TLS private key
- `/opt/openbao/data/` - Raft data directory

## Backups

Raft snapshots can be taken with:

```bash
bao operator raft snapshot save /opt/openbao/snapshots/backup-$(date +%Y%m%d).snap
```

The VM is also backed up via Proxmox VM backups.

## Related

- Issue #62 - Original implementation plan
- Issue #63 - Let's Encrypt automation (blocked by OpenBao for Cloudflare token storage)
