#!/usr/bin/env bash
# Export the PoC instance as a seed for the homelab deploy (docs/immich.md).
#
# 1. pg_dumpall (Immich's documented backup form) -> $OUT/immich-seed.sql.gz
# 2. rsync the upload location (thumbs, previews, ...) straight to the homelab
#    share via the containers host (sudo rsync there so ownership is kept).
#
# Only the Postgres container is started; server/ML stay down. Safe to re-run:
# the rsync is incremental and the dump is overwritten.
#
# Usage: ./export-seed.sh            (dump + sync)
#        ./export-seed.sh dump-only
set -euo pipefail
cd "$(dirname "$0")"; set -a; . ./.env; set +a
OUT=${OUT:-/mnt/data/immich-poc/seed}
export UID GID=$(id -g)

mkdir -p "$OUT"
docker compose up -d database >/dev/null
for i in $(seq 1 30); do docker exec immich_postgres pg_isready -U postgres -q && break; sleep 2; done

echo "dumping database..."
docker exec -t immich_postgres pg_dumpall --clean --if-exists --username=postgres | gzip > "$OUT/immich-seed.sql.gz"
ls -lh "$OUT/immich-seed.sql.gz"

docker compose stop database >/dev/null

if [ "${1:-}" = dump-only ]; then echo "dump in $OUT"; exit 0; fi

KEY=${DEPLOY_KEY:-$(git rev-parse --show-toplevel)/ansible/keys/deploy}
TARGET=${SEED_TARGET:-deploy@10.10.15.11}
echo "syncing library to $TARGET:/mnt/nas/immich/library/ ..."
rsync -a --info=progress2 -e "ssh -i $KEY" --rsync-path="sudo rsync" "$UPLOAD_LOCATION/" "$TARGET:/mnt/nas/immich/library/"
scp -q -i "$KEY" "$OUT/immich-seed.sql.gz" "$TARGET:/tmp/immich-seed.sql.gz"
echo "seed delivered — restore per docs/immich.md"
