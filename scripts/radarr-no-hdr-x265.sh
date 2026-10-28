#!/usr/bin/env bash
# Push "HEVC x265" and "HDR" custom formats into Radarr and wire them into the
# HD-1080p quality profile (score -10000, minFormatScore=0) so HEVC/x265 and
# HDR/Dolby-Vision releases are rejected at grab time. Idempotent.
#
# WHY THIS EXISTS: on an old (non-HDR, non-HEVC) Chromecast, an x265 file
# forces a full HEVC->H264 transcode and an HDR/Dolby-Vision file additionally
# forces HDR->SDR tone-mapping every play — the heaviest path, prone to
# stutter and washed-out colour. Auto-upgrade would otherwise happily grab a
# UHD-derived "1080p HDR10 DoVi x265" release over a clean SDR H264 WEB-DL
# (it's a higher quality tier), silently reintroducing the problem. These two
# custom formats keep Radarr on SDR H264 that direct-plays.
#
# To grab an HDR/x265 release DELIBERATELY (e.g. you've moved to a 4K HDR
# client), use Radarr's interactive search — a manual grab bypasses
# custom-format rejection without weakening this rule for everything else.
#
# Companion to scripts/radarr-english-only.sh and scripts/arr-quality-caps.sh.
#
# Pulls Radarr's API key from /config/config.xml inside the running container
# over SSH — no need to copy it from the UI. SSHes as your user (in the docker
# group on containers), not deploy.
#
# Usage:
#   scripts/radarr-no-hdr-x265.sh
#
# Overrides:
#   SSH_HOST=cwage@containers.lan.quietlife.net  (default)
#   RADARR_URL=https://radarr.lan.quietlife.net  (default)
#   QP_NAME=HD-1080p                             (default)
#
# Requires: ssh, curl, jq

set -euo pipefail

SSH_HOST="${SSH_HOST:-cwage@containers.lan.quietlife.net}"
RADARR_URL="${RADARR_URL:-https://radarr.lan.quietlife.net}"
QP_NAME="${QP_NAME:-HD-1080p}"
CF_SCORE=-10000

echo "Fetching Radarr API key from $SSH_HOST ..."
RADARR_API_KEY=$(ssh -o BatchMode=yes "$SSH_HOST" 'docker exec radarr cat /config/config.xml' \
  | sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p')
[[ -n "$RADARR_API_KEY" ]] || { echo "ERROR: could not extract API key from config.xml"; exit 1; }
echo "  got key (${#RADARR_API_KEY} chars)"

call() {
  curl -fsS -H "X-Api-Key: $RADARR_API_KEY" -H "Content-Type: application/json" "$@"
}

echo "Checking $RADARR_URL ..."
call "$RADARR_URL/api/v3/system/status" >/dev/null
echo "  API key OK"

# ensure_cf NAME REGEX -> prints the custom format id on stdout (creates if
# missing). A ReleaseTitleSpecification matches the regex against the release
# title; negate=false + required=true means "format applies when title matches".
ensure_cf() {
  local name="$1" regex="$2" existing
  existing=$(call "$RADARR_URL/api/v3/customformat" \
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
  id=$(call -X POST "$RADARR_URL/api/v3/customformat" -d "$body" | jq -r '.id')
  echo "  created custom format '$name' (id=$id)" >&2
  echo "$id"
}

echo "Ensuring custom formats ..."
X265_ID=$(ensure_cf "HEVC x265" '\b([hx]\.?265|hevc)\b')
HDR_ID=$(ensure_cf "HDR" '\b(HDR10\+?|HDR|Dolby[ .]?Vision|DoVi|HLG|PQ10)\b')

echo "Updating quality profile '$QP_NAME' ..."
qp=$(call "$RADARR_URL/api/v3/qualityprofile" \
  | jq --arg n "$QP_NAME" '.[] | select(.name == $n)')
if [[ -z "$qp" ]]; then
  echo "ERROR: no quality profile named '$QP_NAME' in Radarr"
  echo "Available profiles:"
  call "$RADARR_URL/api/v3/qualityprofile" | jq -r '.[].name | "  - " + .'
  exit 1
fi
qp_id=$(jq -r '.id' <<<"$qp")

# Set our two CFs to the penalty score, preserving every other formatItem.
# New custom formats are auto-added to all profiles at score 0, but append
# them defensively in case this profile predates them.
new_qp=$(jq \
  --argjson x265 "$X265_ID" --argjson hdr "$HDR_ID" --argjson score "$CF_SCORE" '
    .minFormatScore = 0
    | .formatItems = (
        [.formatItems[] | if (.format == $x265 or .format == $hdr) then .score = $score else . end]
      )
    | .formatItems += (if ([.formatItems[].format] | index($x265)) == null
        then [{format:$x265, name:"HEVC x265", score:$score}] else [] end)
    | .formatItems += (if ([.formatItems[].format] | index($hdr)) == null
        then [{format:$hdr, name:"HDR", score:$score}] else [] end)
  ' <<<"$qp")

call -X PUT "$RADARR_URL/api/v3/qualityprofile/$qp_id" -d "$new_qp" >/dev/null
echo "  minFormatScore=0; 'HEVC x265' & 'HDR' score=$CF_SCORE"
echo ""
echo "Done. HEVC/x265 and HDR/Dolby-Vision releases are now rejected in the '$QP_NAME' profile."
echo "To grab one on purpose, use Radarr's interactive search (manual grabs bypass this)."
