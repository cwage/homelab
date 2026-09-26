#!/usr/bin/env bash
# Pause or resume all Immich job queues (PoC).  Usage: ./immich-jobs.sh pause|resume|status
set -euo pipefail
cd "$(dirname "$0")"; set -a; . ./.env; set +a
IMMICH_URL=${IMMICH_URL:-http://127.0.0.1:2283}
api() { curl -sS -H "x-api-key: $IMMICH_API_KEY" -H 'Content-Type: application/json' "$IMMICH_URL/api$1" "${@:2}"; }
QUEUES="library sidecar metadataExtraction thumbnailGeneration smartSearch ocr duplicateDetection faceDetection facialRecognition"
case "${1:-status}" in
  pause|resume)
    for q in $QUEUES; do api "/jobs/$q" -X PUT -d "{\"command\":\"$1\",\"force\":false}" -o /dev/null; done ;;&
  *)
    api /jobs | jq -r 'to_entries[] | select(.value.jobCounts.waiting+.value.jobCounts.active>0 or .value.queueStatus.isPaused)
      | "\(.key): active=\(.value.jobCounts.active) waiting=\(.value.jobCounts.waiting) paused=\(.value.queueStatus.isPaused)"' ;;
esac
