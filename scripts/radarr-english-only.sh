#!/usr/bin/env bash
# Push a "Language: Not English" custom format into Radarr and wire it
# into the HD-1080p quality profile (score -10000, minFormatScore=0), so
# non-English releases are rejected at grab time. Also disallows
# Remux-1080p in that profile so Radarr prefers compact Bluray-1080p
# encodes over 30GB+ lossless remuxes (overkill for a 720p-capped
# Chromecast). Idempotent.
#
# Radarr counterpart of scripts/sonarr-english-only.sh.
#
# Pulls Radarr's API key from /config/config.xml inside the running
# container over SSH -- no need to copy it from the UI. SSHes as your
# user (in the docker group on containers), not deploy.
#
# Usage:
#   scripts/radarr-english-only.sh
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
CF_NAME="Language: Not English"
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

existing=$(call "$RADARR_URL/api/v3/customformat" \
  | jq -r --arg n "$CF_NAME" '.[] | select(.name == $n) | .id // empty')

if [[ -z "$existing" ]]; then
  cf_body='{
    "name": "Language: Not English",
    "includeCustomFormatWhenRenaming": false,
    "specifications": [
      {
        "name": "Not English Language",
        "implementation": "LanguageSpecification",
        "negate": true,
        "required": false,
        "fields": [ { "name": "value", "value": 1 } ]
      }
    ]
  }'
  echo "Creating custom format '$CF_NAME' ..."
  cf_id=$(call -X POST "$RADARR_URL/api/v3/customformat" -d "$cf_body" | jq -r '.id')
  echo "  created (id=$cf_id)"
else
  cf_id="$existing"
  echo "Custom format '$CF_NAME' already exists (id=$cf_id)"
fi

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

new_qp=$(jq \
  --argjson cf_id "$cf_id" \
  --arg cf_name "$CF_NAME" \
  --argjson score "$CF_SCORE" '
    .minFormatScore = 0
    | .items = (.items | map(
        if .quality.name == "Remux-1080p" then .allowed = false else . end
      ))
    | .formatItems = (
        [.formatItems[] | select(.format != $cf_id)]
        + [{format: $cf_id, name: $cf_name, score: $score}]
      )
  ' <<<"$qp")

call -X PUT "$RADARR_URL/api/v3/qualityprofile/$qp_id" -d "$new_qp" >/dev/null
echo "  minFormatScore=0; '$CF_NAME' score=$CF_SCORE; Remux-1080p disallowed"
echo ""
echo "Done."
echo "Next: set the Add-Movie default quality profile to '$QP_NAME' in the"
echo "Radarr UI (Add Movie -> pick HD-1080p; Radarr remembers it). New movies"
echo "will then default to 1080p and reject non-English releases."
