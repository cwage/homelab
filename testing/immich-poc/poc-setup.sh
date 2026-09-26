#!/usr/bin/env bash
# Configure a fresh Immich instance for the archive PoC via the REST API:
#   - top-quality SigLIP2 CLIP model
#   - use embedded RAW previews instead of demosaicing
#   - create a read-only external library over a set of /mnt/nas/Pictures folders
#   - kick off the scan
#
# Usage: IMMICH_API_KEY=... ./poc-setup.sh <folder-glob>...
#   e.g. IMMICH_API_KEY=... ./poc-setup.sh '2015-*' '2018-*'   (one library per glob)
# Create the key in the web UI: Account settings -> API keys.
set -euo pipefail

IMMICH_URL=${IMMICH_URL:-http://127.0.0.1:2283}
: "${IMMICH_API_KEY:?set IMMICH_API_KEY}"
PICTURES=/mnt/nas/Pictures

api() { curl -sS --fail-with-body -H "x-api-key: $IMMICH_API_KEY" -H 'Content-Type: application/json' "$IMMICH_URL/api$1" "${@:2}"; }

# --- system config -----------------------------------------------------------
api /system-config \
  | jq '.machineLearning.clip.modelName = "ViT-SO400M-16-SigLIP2-384__webli"
        | .image.extractEmbedded = true' \
  | api /system-config -X PUT -d @- >/dev/null
echo "system config: SigLIP2 model + embedded previews"

# --- one external library per glob ------------------------------------------
# (the API rejects libraries with more than ~128 import paths; the full archive
#  later is a single import path: /mnt/nas/Pictures)
owner=$(api /users/me | jq -r .id)
for glob in "$@"; do
  paths=()
  for d in "$PICTURES"/$glob; do [ -d "$d" ] && paths+=("$d"); done
  [ ${#paths[@]} -gt 0 ] || { echo "no folders matched $glob" >&2; continue; }
  body=$(jq -n --arg owner "$owner" --arg name "Pictures $glob" --args '{
    ownerId: $owner,
    name: $name,
    importPaths: $ARGS.positional,
    exclusionPatterns: [
      "**/#recycle/**", "**/@eaDir/**", "**/Recycled/**",
      "**/*.mov", "**/*.MOV", "**/*.mp4", "**/*.MP4", "**/*.avi", "**/*.AVI", "**/*.dv"
    ]
  }' "${paths[@]}")
  resp=$(api /libraries -X POST -d "$body") || { echo "create failed for $glob: $resp" >&2; exit 1; }
  lib=$(jq -r .id <<<"$resp")
  api "/libraries/$lib/scan" -X POST -d '{}' >/dev/null
  echo "library '$glob': ${#paths[@]} folders, scan queued"
done
echo "watch progress at $IMMICH_URL/admin/jobs-status"
