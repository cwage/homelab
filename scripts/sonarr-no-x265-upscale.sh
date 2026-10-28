#!/usr/bin/env bash
# Push "HEVC x265" and "AI Upscale" custom formats into Sonarr and wire them
# into the SD quality profile (score -10000, minFormatScore=0) so x265/HEVC
# encodes and AI-upscaled releases are rejected at grab time. Idempotent.
#
# WHY THIS EXISTS: SD-only shows (e.g. Star Trek: DS9 — no official HD
# remaster) attract bloated x265 "DVDRip" packs and 20GB+ AI-upscaled
# fake-1080p releases. Sonarr classifies those as "DVD" quality, so the plain
# SD profile happily grabs them (it filters on resolution/source, not codec).
# These two custom formats reject both, leaving clean x264/XviD that
# direct-plays on a Chromecast with no HEVC transcode.
#
# To grab an x265 pack DELIBERATELY (e.g. a season with no x264 source, like
# DS9 S05/S07), use Sonarr's interactive search — a manual grab bypasses
# custom-format rejection without weakening this rule for everything else.
#
# Companion to scripts/sonarr-english-only.sh and scripts/arr-quality-caps.sh.
#
# Pulls Sonarr's API key from /config/config.xml inside the running container
# over SSH — no need to copy it from the UI. SSHes as your user (in the docker
# group on containers), not deploy.
#
# Usage:
#   scripts/sonarr-no-x265-upscale.sh
#
# Overrides:
#   SSH_HOST=cwage@containers.lan.quietlife.net  (default)
#   SONARR_URL=https://sonarr.lan.quietlife.net  (default)
#   QP_NAME=SD                                   (default)
#
# Requires: ssh, curl, jq

set -euo pipefail

SSH_HOST="${SSH_HOST:-cwage@containers.lan.quietlife.net}"
SONARR_URL="${SONARR_URL:-https://sonarr.lan.quietlife.net}"
QP_NAME="${QP_NAME:-SD}"
CF_SCORE=-10000

echo "Fetching Sonarr API key from $SSH_HOST ..."
SONARR_API_KEY=$(ssh -o BatchMode=yes "$SSH_HOST" 'docker exec sonarr cat /config/config.xml' \
  | sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p')
[[ -n "$SONARR_API_KEY" ]] || { echo "ERROR: could not extract API key from config.xml"; exit 1; }
echo "  got key (${#SONARR_API_KEY} chars)"

call() {
  curl -fsS -H "X-Api-Key: $SONARR_API_KEY" -H "Content-Type: application/json" "$@"
}

echo "Checking $SONARR_URL ..."
call "$SONARR_URL/api/v3/system/status" >/dev/null
echo "  API key OK"

# ensure_cf NAME REGEX -> prints the custom format id on stdout (creates if
# missing). A ReleaseTitleSpecification matches the regex against the release
# title; negate=false + required=true means "format applies when title matches".
ensure_cf() {
  local name="$1" regex="$2" existing
  existing=$(call "$SONARR_URL/api/v3/customformat" \
    | jq -r --arg n "$name" '.[] | select(.name == $n) | .id // empty')
  if [[ -n "$existing" ]]; then
    echo "  custom format '$name' already exists (id=$existing)" >&2
    echo "$existing"; return
  fi
  local body
  body=$(jq -nc --arg n "$name" --arg r "$regex" '{
    name: $n,
    includeCustomFormatWhenRenaming: false,
    specifications: [{
      name: $n, implementation: "ReleaseTitleSpecification",
      negate: false, required: true,
      fields: [{ name: "value", value: $r }]
    }]
  }')
  local id
  id=$(call -X POST "$SONARR_URL/api/v3/customformat" -d "$body" | jq -r '.id')
  echo "  created custom format '$name' (id=$id)" >&2
  echo "$id"
}

echo "Ensuring custom formats ..."
X265_ID=$(ensure_cf "HEVC x265" '\b([hx]\.?265|hevc)\b')
UPSCALE_ID=$(ensure_cf "AI Upscale" '\bupscale')

echo "Updating quality profile '$QP_NAME' ..."
qp=$(call "$SONARR_URL/api/v3/qualityprofile" \
  | jq --arg n "$QP_NAME" '.[] | select(.name == $n)')
if [[ -z "$qp" ]]; then
  echo "ERROR: no quality profile named '$QP_NAME' in Sonarr"
  echo "Available profiles:"
  call "$SONARR_URL/api/v3/qualityprofile" | jq -r '.[].name | "  - " + .'
  exit 1
fi
qp_id=$(jq -r '.id' <<<"$qp")

# Set our two CFs to the penalty score, preserving every other formatItem.
# New custom formats are auto-added to all profiles at score 0, but append
# them defensively in case this profile predates them.
new_qp=$(jq \
  --argjson x265 "$X265_ID" --argjson up "$UPSCALE_ID" --argjson score "$CF_SCORE" '
    .minFormatScore = 0
    | .formatItems = (
        [.formatItems[] | if (.format == $x265 or .format == $up) then .score = $score else . end]
      )
    | .formatItems += (if ([.formatItems[].format] | index($x265)) == null
        then [{format:$x265, name:"HEVC x265", score:$score}] else [] end)
    | .formatItems += (if ([.formatItems[].format] | index($up)) == null
        then [{format:$up, name:"AI Upscale", score:$score}] else [] end)
  ' <<<"$qp")

call -X PUT "$SONARR_URL/api/v3/qualityprofile/$qp_id" -d "$new_qp" >/dev/null
echo "  minFormatScore=0; 'HEVC x265' & 'AI Upscale' score=$CF_SCORE"
echo ""
echo "Done. x265/HEVC and AI-upscaled releases are now rejected in the '$QP_NAME' profile."
echo "To grab one on purpose, use Sonarr's interactive search (manual grabs bypass this)."
