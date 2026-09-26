# Immich

Semantic search over the photo archive (`/mnt/nas/Pictures`, ~230k RAW/JPEG,
20 years). Tracking issue: #333. Compose services live in
`hosts/containers/stacks/docker-compose.yml` under the Immich comment block.

## Shape

| Piece | Where | Why |
|---|---|---|
| Photos | `/mnt/nas/Pictures`, mounted **read-only** | External library: indexed in place, never copied or written |
| Upload location (thumbs, previews, DB dumps) | `/mnt/nas/immich/library` (NFS, rw) | ~125 GB; far too big for the 64 GB VM disk |
| Postgres | named volume `immich_db` on the VM disk | Immich does not support network shares for the DB |
| ML | `immich-ml`, **CPU** | The SigLIP2 visual model does not fit the 1050 Ti (4 GB). New-photo volume is tiny, so CPU is fine. Search only needs the small text model. |
| Models | `ViT-SO400M-16-SigLIP2-384__webli` (CLIP), `buffalo_l` (faces) | Config lives in the DB and comes with the seed. **Do not change the CLIP model** without accepting a full re-embed. |

The instance was **seeded from a workstation PoC** (`testing/immich-poc/`)
where a 3060 Ti did the one-time heavy lifting: thumbnails, CLIP embeddings
and face detection/recognition for the whole archive. The homelab never
re-does that work; it only processes photos added after the seed.

Metadata edited in the Immich UI for external-library assets (tags, dates,
favourites) is stored only in Immich's DB and never written to the files.
Person names are also DB-only. Both travel with DB dumps.

## Secrets

`IMMICH_DB_PASSWORD` is a line in the compose `.env`, which openbao-agent
renders from `kv/stacks/containers/env` (`content` field, whole file body).
Add the line to that secret's content, then `compose up -d` on the host so the
new env reaches the containers. A-Za-z0-9 only (Immich constraint).

## Runbooks

### First deploy (seeded)

1. `make nas-apply` (or the nas playbook) to create the `immich` share on portanas; `make tofu-plan` → read it → `make tofu-apply` for the VM bump (8 cores / 16 GB; expect *update in-place*, stop if it says replace). The VM needs a reboot for the new memory to take effect.
2. `make nix-deploy-host HOST=dns1 TARGET=10.10.15.15` (CNAME), then `HOST=containers TARGET=10.10.15.11` (mount, compose, backups).
3. From the workstation, `testing/immich-poc/export-seed.sh` dumps the PoC DB and rsyncs its library straight onto the share via the containers host (uses the repo deploy key + sudo rsync there). The dump lands in `/tmp/immich-seed.sql.gz` on `containers`. Before that, make sure `/mnt/nas/immich/library` exists and is owned by uid 1000 — if Docker creates it, it's root-owned and the server can't write.
4. On `containers`, stop the app, keep the database, restore (Immich's documented restore; the `sed` fixes `search_path` for the vector extension), start the app:
   ```
   cd /opt/stacks && docker compose stop immich-server immich-ml
   gunzip < /tmp/immich-seed.sql.gz | sed "s/SELECT pg_catalog.set_config('search_path', '', false);/SELECT pg_catalog.set_config('search_path', 'public, pg_catalog', true);/g" | docker exec -i immich-db psql --dbname=postgres --username=postgres
   docker compose up -d immich-server immich-ml
   ```
   `pg_dumpall` also restores the source's `postgres` role password, so the server will fail auth until the role is reset to this host's value. Read it from `.env` and feed it via stdin (never on a command line):
   ```
   PW=$(sudo grep "^IMMICH_DB_PASSWORD=" /opt/stacks/.env | cut -d= -f2-); printf "ALTER ROLE postgres PASSWORD '%s';\n" "$PW" | docker exec -i immich-db psql -U postgres -q; docker compose restart immich-server
   ```
5. Log in with the PoC admin account at `https://immich.lan.quietlife.net`. Administration → External Libraries → the `Pictures` library should already point at `/mnt/nas/Pictures` (identical path on both hosts). Trigger a scan; it should find nothing new and finish in minutes.
6. Delete `/tmp/immich-seed.sql.gz` on `containers` once verified (it contains the whole DB, including password hashes).

### Adding new photos

Copy them into `/mnt/nas/Pictures/<date>/` as always, then Administration →
External Libraries → scan. Only new files get processed (metadata, thumbnail,
CLIP on CPU: a few seconds each, faces).

### Bulk re-runs (re-thumbnail, re-embed, faces)

`immich-server` leaks memory during bulk jobs: on the PoC it reached 20+ GB
and either OOM-cycled at its cap or crawled beneath it. The container has
`mem_limit: 6g`; a bulk job on this host **will** hit that. Run bulk work with
a guard that restarts the container when memory passes a threshold — a loop
around `docker stats` + `docker compose restart immich-server` every few
minutes is enough — and with job concurrency set low (Administration →
Settings → Job Settings). Better: do it on the workstation PoC and re-seed.

Also watch `docker logs immich-ml` for `Falling back to ['CPUExecutionProvider']`
if GPU ML is ever enabled here; the PoC lost CUDA silently once.

### Backups

Immich writes a nightly `pg_dumpall` to `/mnt/nas/immich/library/backups/`
(Administration → Settings → Backup). The `immich` share is in the local
backup sweep (`modules/backups.nix`, `local.paths`) but **not** B2: thumbnails
are regenerable and 125 GB of them is not worth the egress. If the DB dumps
alone should reach B2, add a narrower path later.

### Restore from Immich's own dump

Same as step 4 above with the latest file in `library/backups/`.

## Search tips

- Free-text search is CLIP: describe the *picture* ("dog on a couch", "night sky"), not a filename.
- The filter panel narrows by date, camera, folder path, people.
- There is **no** descriptive text per photo: the sidecars have no keywords and Flickr was dropped (issue #333). If that ever matters, captioning via a vision model into the sidecars is the path.
