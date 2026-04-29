# Backup tooling — workstation rclone shell

Dockerized rclone container for **ad-hoc workstation-level testing** against the homelab's B2-encrypted and local-USB backup targets. Uses the same OpenBao secret paths as the production scheduler so manual runs and scheduled runs see identical state.

> **This is not the production scheduler.** Daily B2, local-USB, and config-snapshot backups run on `containers2` as systemd timers declared in [`modules/backups.nix`](../modules/backups.nix), wired up from [`hosts/containers2/configuration.nix`](../hosts/containers2/configuration.nix). If you're trying to change *what* gets backed up or *when*, edit those — not this directory.

See [issue #113](https://github.com/cwage/homelab/issues/113) for the broader strategy and disaster recovery plan.

## What's here

A small Docker image with rclone preconfigured for two remotes:

| Remote | Description |
|--------|-------------|
| `b2:` | Raw Backblaze B2 (unencrypted) |
| `b2crypt:` | rclone crypt overlay — what backups actually write to |

Local backups use plain filesystem paths under `/backup/local/`.

## OpenBao secret layout

The container's entrypoint fetches credentials from OpenBao at run time. The same paths back the production NixOS units, so anything you change here propagates.

| KV path | Fields |
|---------|--------|
| `kv/backup/backblaze` | `account_id`, `application_key` |
| `kv/backup/rclone-crypt` | `password` (this remote uses the default rclone salt — no `password2`) |
| `kv/backup/remote-token` | `token` — the periodic token scoped to the `backup-remote` policy |

The `backup-remote` policy:

```hcl
path "kv/data/backup/backblaze"     { capabilities = ["read"] }
path "kv/data/backup/rclone-crypt"  { capabilities = ["read"] }
```

### Token rotation

```bash
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login  # enter root token

bao token revoke <old-token>
# Then run `bao token create -policy=backup-remote -no-default-policy -orphan -period=8760h -display-name=backup-remote`
# yourself and capture the output. Don't paste the token here — store it directly:
bao kv put kv/backup/remote-token token=-   # then paste the new token at stdin
```

containers2's openbao-agent re-reads `kv/backup/*` automatically; no redeploy needed for token rotation, only for changes that alter the agent template (see `hosts/containers2/configuration.nix`).

## Workstation usage

```bash
make backup-build                                # build the image once
make backup-shell                                # interactive shell w/ rclone configured
make backup-shell CMD='rclone lsd b2:'           # list buckets
make backup-shell CMD='rclone ls b2crypt:'       # list encrypted file tree
make backup-b2-dry                               # dry-run a full B2 sweep
make backup-local-dry                            # dry-run a full local sweep
```

`make backup-b2` and `make backup-local` will run an actual sync from the workstation if you really want to — but by default the production schedule on containers2 already covers this.

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
├── Dockerfile.rsync     # alpine+rsync helper image (tag: homelab-rsync:1)
├── docker-compose.yml   # workstation service definition
├── Makefile             # build/shell/sync targets
├── .env.example         # credentials template
├── targets/
│   ├── b2.txt           # NAS paths included in B2 sweeps
│   └── local.txt        # NAS paths included in local sweeps
└── scripts/
    ├── entrypoint.sh    # fetches secrets, configures rclone
    ├── backup.sh        # unified b2/local sweep
    └── backup-configs.sh  # workstation-side helper for the configs snapshot flow
```

> The `targets/*.txt` and `scripts/backup.sh` paths here are mirrored — but not enforced to match — `homelab.backups.{b2,local,configs}` in `hosts/containers2/configuration.nix`. If you change the production list, update these too (or accept that the workstation tool will diverge).
