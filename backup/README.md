# Backup Tooling

Dockerized backup tooling for syncing NAS shares to multiple targets using rclone.

See [issue #113](https://github.com/cwage/homelab/issues/113) for the full backup strategy and disaster recovery plan.

## Overview

The backup system runs as an **ephemeral Docker container** on the containers host. A unified `backup.sh` script supports multiple targets via the `--target` flag:

| Target | Destination | Encryption | Cost |
|--------|-------------|------------|------|
| `b2` | Backblaze B2 | rclone crypt (client-side) | Paid |
| `local` | USB drive (`/backup/local`) | None | Free |

A daily cron job launches the container for B2 backups, which fetches credentials from OpenBao at runtime. Local USB backups can be run manually or scheduled separately.

## OpenBao Secrets Setup

All commands below run on the OpenBao server (or from a workstation with `bao` CLI configured).

### 1. Store B2 credentials

Get your Backblaze B2 API credentials from Backblaze B2 > App Keys.

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login  # enter root token

bao kv put kv/backup/backblaze \
  account_id="your_b2_account_id" \
  application_key="your_b2_application_key"
```

### 2. Store rclone crypt credentials

These are the client-side encryption keys for the rclone crypt overlay.

```bash
bao kv put kv/backup/rclone-crypt \
  password="your_encryption_password" \
  password2="your_salt"
```

### 3. Create the `backup-remote` policy

This policy scopes the backup container's token to only the two KV paths it needs:

```bash
bao policy write backup-remote - <<'EOF'
path "kv/data/backup/backblaze" {
  capabilities = ["read"]
}
path "kv/data/backup/rclone-crypt" {
  capabilities = ["read"]
}
EOF
```

### 4. Create a periodic token

```bash
bao token create \
  -policy=backup-remote \
  -no-default-policy \
  -orphan \
  -period=8760h \
  -display-name="backup-remote"
```

Save the token from the output.

### 5. Store the token in KV

This allows Ansible to retrieve it at deploy time:

```bash
bao kv put kv/backup/remote-token token="<token-from-step-4>"
```

## Deployment

Deploy the backup system to the containers host:

```bash
make ansible-backup-deploy
```

This playbook:
1. Copies Dockerfile, scripts, and target configs to `/opt/backup/`
2. Fetches the `backup-remote` token from `kv/backup/remote-token` (using the Ansible deploy token)
3. Writes `/opt/backup/.env` with OpenBao connection params only (`BAO_ADDR`, `BAO_TOKEN`). TLS verification is enabled by default; `BAO_SKIP_VERIFY` is only set to `true` if the Ansible environment has it enabled (bootstrap only).
4. Builds the backup container image
5. Removes any legacy persistent backup container
6. Installs a daily cron job for the `deploy` user

## Scheduled Backups

| Setting | Value |
|---------|-------|
| Schedule | Daily — B2 at 3:40 AM, local at 2:00 AM |
| Host | `containers.lan.quietlife.net` |
| User | `deploy` |
| Cron names | `backup-b2-daily`, `backup-local-daily` |
| Container | Ephemeral (`docker compose run --rm`) |
| Credentials | B2: fetched from OpenBao at runtime. Local: none needed |

The cron job runs:

```bash
flock -n /opt/backup/logs/backup-b2.cron.lock -c 'cd /opt/backup && docker compose run --rm -T backup /opt/backup/scripts/backup.sh --target b2 >> /opt/backup/logs/cron.log 2>&1'
```

The `flock` wrapper prevents overlapping runs — if a previous backup is still running when cron fires, the new invocation exits immediately rather than starting a concurrent sync.

View the cron entry:

```bash
crontab -u deploy -l
```

## USB Drive Setup (Local Backups)

The Seagate 12TB USB drive is passed through to the containers VM via Proxmox USB passthrough (device `0bc2:2038`).

Inside the containers VM:
1. Drive is mounted at `/mnt/nasbak` via fstab (`UUID=479d8cc7-5779-4707-bb19-87b555d7580b`, `nofail`)
2. Docker Compose mounts `/mnt/nasbak:/backup/local` into the container

The backup script checks that `/backup/local` is mounted before proceeding with local backups.

## Notifications

Backup results are sent to [ntfy.sh](https://ntfy.sh) for push notifications to your phone.

| Event | Priority | Tags |
|-------|----------|------|
| All paths synced successfully | `default` | `white_check_mark` |
| One or more paths failed | `urgent` | `x` |

Notifications include the target name (B2/LOCAL), duration, and a summary of what succeeded/failed. Dry runs do not send notifications.

The ntfy topic URL is configured via the `NTFY_TOPIC` environment variable in `.env`. If unset or empty, notifications are silently skipped (the backup still runs normally). The topic is deployed by Ansible from the `ntfy_backup_topic` variable in `group_vars/container_hosts.yml`.

To test notifications manually:

```bash
curl -d "test notification" https://ntfy.sh/your-topic-here
```

## Token Rotation

When the `backup-remote` token needs to be rotated:

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login  # enter root token

# 1. Revoke the old token
bao token revoke <old-token>

# 2. Create a new token
bao token create \
  -policy=backup-remote \
  -no-default-policy \
  -orphan \
  -period=8760h \
  -display-name="backup-remote"

# 3. Update the stored token
bao kv put kv/backup/remote-token token="<new-token>"
```

Then re-deploy to push the new token to the containers host:

```bash
make ansible-backup-deploy
```

## Manual Runs / Troubleshooting

### Run a B2 backup manually

```bash
ssh containers.lan.quietlife.net
cd /opt/backup
docker compose run --rm backup /opt/backup/scripts/backup.sh --target b2 --interactive
```

### Run a local USB backup

```bash
docker compose run --rm backup /opt/backup/scripts/backup.sh --target local --interactive
```

### Dry run (no changes)

```bash
docker compose run --rm backup /opt/backup/scripts/backup.sh --target b2 --dry-run
docker compose run --rm backup /opt/backup/scripts/backup.sh --target local --dry-run
```

### Interactive shell

```bash
docker compose run --rm backup bash
# Inside the container:
rclone lsd b2crypt:          # list encrypted bucket contents
rclone ls b2crypt:Pictures   # list files in a share
ls /backup/local/            # list local backup contents
```

### Logs

Backup logs are stored in `/opt/backup/logs/` on the containers host:
- `b2-YYYYMMDD-HHMMSS.log` — per-run B2 rclone logs
- `local-YYYYMMDD-HHMMSS.log` — per-run local rclone logs
- `cron.log` — cron job stdout/stderr

### Local development

For local testing, copy `.env.example` to `.env` and fill in credentials:

```bash
cd backup/
cp .env.example .env
# Edit .env with your credentials
make build
make shell
```

## Security Model

The backup system uses a two-layer credential approach:

1. **On disk** (`/opt/backup/.env`): Only an OpenBao token scoped to `backup-remote` policy (can only read `kv/backup/backblaze` and `kv/backup/rclone-crypt`)
2. **At runtime**: The container entrypoint fetches B2 and rclone-crypt credentials from OpenBao via API, exports them as environment variables, and runs the backup. Credentials are never written to disk.

If the `.env` file is compromised, the attacker gets an OpenBao token that can only read two specific KV paths — not the full secrets engine or any other infrastructure secrets.

## rclone Remotes

The entrypoint configures two rclone remotes via environment variables:

| Remote | Description |
|--------|-------------|
| `b2:` | Raw Backblaze B2 access (unencrypted) |
| `b2crypt:` | Encrypted overlay — use this for backups |

Local backups use plain filesystem paths (`/backup/local/`) — no rclone remote needed.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make backup-build` | Build the backup container image |
| `make backup-shell` | Open interactive shell with rclone configured |
| `make backup-shell CMD='...'` | Run a specific command in the container |
| `make backup-clean` | Remove the backup container image |
| `make backup-b2` | Sync NAS to Backblaze B2 (encrypted) |
| `make backup-b2-dry` | Dry-run B2 backup |
| `make backup-local` | Sync NAS to USB drive |
| `make backup-local-dry` | Dry-run local backup |
| `make backup-help` | Show available targets |

## Files

```
backup/
├── Dockerfile              # Container image definition
├── docker-compose.yml      # Local dev service configuration
├── Makefile                # Build and run targets
├── .env.example            # Template for credentials
├── README.md               # This file
├── logs/                   # Backup logs (gitignored)
├── targets/
│   ├── b2.txt              # Paths for B2 backup
│   └── local.txt           # Paths for USB backup
└── scripts/
    ├── entrypoint.sh       # Fetches secrets and configures rclone
    └── backup.sh           # Unified backup script (--target b2|local)
```
