# Immich proof-of-concept (workstation)

Local, throwaway-able Immich stack for evaluating semantic search over the photo
archive before it moves to the homelab. Tracking issue: #333.

- Indexes `/mnt/nas/Pictures` **in place, read-only** (external library). Nothing on the NAS is written.
- CUDA machine learning on the workstation GPU.
- All state under `/mnt/data/immich-poc/` (library thumbnails, Postgres, model cache).
- Container paths match the homelab `containers` host so the DB can be dumped and restored there later without re-scanning.

## Run

```bash
cp .env.example .env   # set DB_PASSWORD (A-Za-z0-9 only)
mkdir -p /mnt/data/immich-poc/{library,postgres,model-cache}
export UID GID=$(id -g)
docker compose up -d
```

Then:

1. Open http://127.0.0.1:2283 and create the admin account.
2. Account settings → API keys → create one.
3. Configure the model, embedded previews, external library and start the scan:

```bash
IMMICH_API_KEY=... ./poc-setup.sh '2015-*' '2018-*'
```

Any set of top-level folder globs works. Widen later by editing the library's import paths in Administration → External Libraries (already-indexed assets are kept, only new paths are scanned).

Progress: Administration → Jobs. Order is library scan → metadata extraction → thumbnails → smart search (CLIP) → face detection. Search only becomes semantic once the Smart Search job has finished.

## Notes

- Model: `ViT-SO400M-16-SigLIP2-384__webli` (top of Immich's quality table, ~2.5 GB download on first run, fits an 8 GB GPU). The homelab 1050 Ti (4 GB) will need a smaller model or a remote ML endpoint.
- `image.extractEmbedded=true` uses the camera's embedded JPEG for RAW thumbnails instead of demosaicing. Much faster; colours match what the camera showed.
- Exclusions: Synology `@eaDir`, `#recycle`, and all video on the first pass.
- Metadata edited in the Immich UI for external assets is stored only in Immich's DB. Keywords must be written to the XMP sidecars from outside (Flickr backfill, later).

## Tear down

```bash
docker compose down            # keep data
docker compose down -v         # plus named volumes (none used; data dirs stay)
rm -rf /mnt/data/immich-poc    # nuke everything
```
