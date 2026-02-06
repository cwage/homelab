# Backup Tooling

Dockerized backup tooling for NAS shares to local USB and Backblaze B2.

See [issue #113](https://github.com/cwage/homelab/issues/113) for the full backup strategy and disaster recovery plan.

## Quick Start

```bash
# Build the container
make backup-build

# Open interactive shell with rclone configured
make backup-shell
```

## Prerequisites

### Option A: OpenBao Secrets (Recommended)

Create the following secrets in OpenBao:

#### `kv/backup/backblaze`

Backblaze B2 API credentials. Get these from Backblaze B2 > App Keys.

| Field | Description |
|-------|-------------|
| `account_id` | B2 Account ID or Application Key ID |
| `application_key` | B2 Application Key |

```bash
bao kv put kv/backup/backblaze \
  account_id="your_account_id" \
  application_key="your_application_key"
```

#### `kv/backup/rclone-crypt`

Client-side encryption credentials for the rclone crypt overlay.

| Field | Description |
|-------|-------------|
| `password` | Encryption password (required) |
| `password2` | Salt for filename encryption (optional but recommended) |

```bash
bao kv put kv/backup/rclone-crypt \
  password="your_encryption_password" \
  password2="your_salt"
```

### Option B: Environment File Fallback

If OpenBao is not available, copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
# Edit .env with your credentials
```

The entrypoint will use `.env` values if OpenBao credentials aren't available.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make backup-build` | Build the backup container image |
| `make backup-shell` | Open interactive shell with rclone configured |
| `make backup-shell CMD='...'` | Run a specific command in the container |
| `make backup-clean` | Remove the backup container image |
| `make backup-help` | Show available targets |

## rclone Remotes

The entrypoint configures two rclone remotes via environment variables:

| Remote | Description |
|--------|-------------|
| `b2:` | Raw Backblaze B2 access (unencrypted) |
| `b2crypt:` | Encrypted overlay - use this for backups |

### Example Commands

```bash
# Inside the container (make backup-shell):

# List B2 buckets
rclone lsd b2:

# List files in bucket (shows encrypted filenames)
rclone ls b2:cwagenas-backup

# List files via crypt overlay (shows decrypted filenames)
rclone ls b2crypt:

# Check what would be synced (dry-run)
rclone sync /mnt/nas/Pictures b2crypt:Pictures --dry-run

# Sync with progress
rclone sync /mnt/nas/Pictures b2crypt:Pictures --progress
```

## Volume Mounts

The container mounts the following paths:

| Container Path | Host Path | Mode | Purpose |
|----------------|-----------|------|---------|
| `/mnt/nas` | `/mnt/nas` | read-only | NAS shares to back up |
| `/backup/local` | `/media/$USER/nasbak` | read-write | USB drive for local backups |
| `/var/log/backup` | `./logs` | read-write | Backup logs |
| `/opt/backup/paths` | `./paths` | read-only | Path configuration files |

## Security Notes

- The OpenBao CLI binary is pinned to a specific version with SHA256 verification (for interactive/admin use)
- The entrypoint fetches secrets from OpenBao via HTTP API using curl/jq, not the CLI
- No secrets are written to disk in the container; rclone is configured via environment variables
- The `.env` file is gitignored
- NAS shares are mounted read-only to prevent accidental modification

## Files

```
backup/
├── Dockerfile              # Container image definition
├── docker-compose.yml      # Service configuration
├── Makefile                # Build and run targets
├── .env.example            # Template for fallback credentials
├── README.md               # This file
├── logs/                   # Backup logs (gitignored)
├── paths/
│   ├── local.txt           # Paths for USB backup (future)
│   └── remote.txt          # Paths for B2 backup (future)
└── scripts/
    └── entrypoint.sh       # Fetches secrets and configures rclone
```
