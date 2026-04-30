# Backup tooling — workstation rclone shell

Dockerized rclone container for **ad-hoc workstation-level testing** against the homelab's B2-encrypted and local-USB backup targets. Uses the same OpenBao secret paths as the production scheduler so manual runs and scheduled runs see identical state.

> **This is not the production scheduler.** Daily B2, local-USB, and config-snapshot backups run on `containers` as systemd timers declared in [`modules/backups.nix`](../modules/backups.nix), wired up from [`hosts/containers/configuration.nix`](../hosts/containers/configuration.nix). If you're trying to change *what* gets backed up or *when*, edit those — not this directory.

See [issue #113](https://github.com/cwage/homelab/issues/113) for the broader strategy and disaster recovery plan.

## What's here

A small Docker image with rclone preconfigured for two remotes:

| Remote | Description |
|--------|-------------|
| `b2:` | Raw Backblaze B2 (unencrypted) |
| `b2crypt:` | rclone crypt overlay — what backups actually write to |

Local backups use plain filesystem paths under `/backup/local/`.

## OpenBao secret layout

The container's entrypoint fetches B2 + rclone-crypt credentials from OpenBao at run time using the periodic token below. **Production reads the same KV data via AppRole** (see `homelab.openbao-agent.secrets` in `hosts/containers/configuration.nix`, which templates fields into `/etc/secrets/backup/`), so the data layer is shared but the auth path is not — rotating the workstation periodic token doesn't affect production and vice versa.

| KV path | Fields | Used by |
|---------|--------|---------|
| `kv/backup/backblaze` | `account_id`, `application_key` | workstation + production |
| `kv/backup/rclone-crypt` | `password` (no `password2` — production omits it deliberately so the crypt remote uses rclone's default salt; setting `password2` here will break compatibility with production-encrypted data) | workstation + production |
| `kv/backup/remote-token` | `token` — periodic token scoped to the `backup-remote` policy | workstation only |

The `backup-remote` policy (used by the workstation periodic token):

```hcl
path "kv/data/backup/backblaze"     { capabilities = ["read"] }
path "kv/data/backup/rclone-crypt"  { capabilities = ["read"] }
```

### Token rotation (workstation)

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login  # enter root token

bao token revoke <old-token>
# Then run `bao token create -policy=backup-remote -no-default-policy -orphan -period=8760h -display-name=backup-remote`
# yourself and capture the output. Don't paste the token here — store it directly:
bao kv put kv/backup/remote-token token=-   # then paste the new token at stdin
```

This only affects the workstation tool. Production runs through openbao-agent's AppRole and reads the cred fields directly — no redeploy needed unless you change the agent template in `hosts/containers/configuration.nix`.

## Workstation usage

```bash
make backup-build                                # build the image once
make backup-shell                                # interactive shell w/ rclone configured
make backup-shell CMD='rclone lsd b2:'           # list buckets
make backup-shell CMD='rclone ls b2crypt:'       # list encrypted file tree
make backup-b2-dry                               # dry-run a full B2 sweep
make backup-local-dry                            # dry-run a full local sweep
```

`make backup-b2` and `make backup-local` will run an actual sync from the workstation if you really want to — but by default the production schedule on containers already covers this.

### Local development

```bash
cd backup/
cp .env.example .env  # fill in BAO_ADDR / BAO_TOKEN
make backup-build
make backup-shell
```

## How it works

1. Entrypoint fetches B2 and rclone-crypt credentials from OpenBao using the token in `.env`
2. Exports them as `RCLONE_CONFIG_*` env vars (never written to disk)
3. Runs the requested command (`rclone`, `bash`, `backup.sh`, …)

If the `.env` file is compromised, the attacker gets a token that can only read two specific KV paths — not the full secrets engine.

## Files

```
backup/
├── Dockerfile           # rclone backup image
├── docker-compose.yml   # workstation service definition
├── Makefile             # build/shell/sync targets
├── .env.example         # credentials template
├── targets/
│   ├── b2.txt           # NAS paths included in B2 sweeps
│   └── local.txt        # NAS paths included in local sweeps
└── scripts/
    ├── entrypoint.sh    # fetches secrets, configures rclone
    └── backup.sh        # unified b2/local sweep
```

> The `targets/*.txt` and `scripts/backup.sh` paths here are mirrored — but not enforced to match — `homelab.backups.{b2,local}` in `hosts/containers/configuration.nix`. If you change the production list, update these too (or accept that the workstation tool will diverge). The container-volume snapshot flow (`backup-configs`) is exclusively a NixOS systemd unit now — see `modules/backups.nix`.
