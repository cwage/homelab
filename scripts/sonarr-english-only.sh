#!/usr/bin/env bash
# Push a "Language: Not English" custom format into Sonarr and wire it
# into the HD-1080p quality profile (score -10000, minFormatScore=0), so
# non-English releases are rejected at grab time. Idempotent.
#
# Pulls Sonarr's API key from /config/config.xml inside the running
# container over SSH — no need to copy it from the UI. SSHes as your
# user (in the docker group on containers), not deploy.
#
# Usage:
#   scripts/sonarr-english-only.sh
#
# Overrides:
#   SSH_HOST=cwage@containers.lan.quietlife.net  (default)
#   SONARR_URL=https://sonarr.lan.quietlife.net  (default)
#   QP_NAME=HD-1080p                             (default)
#
# Requires: ssh, curl, jq

set -euo pipefail

SSH_HOST="${SSH_HOST:-cwage@containers.lan.quietlife.net}"
SONARR_URL="${SONARR_URL:-https://sonarr.lan.quietlife.net}"
QP_NAME="${QP_NAME:-HD-1080p}"
CF_NAME="Language: Not English"
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

existing=$(call "$SONARR_URL/api/v3/customformat" \
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
  cf_id=$(call -X POST "$SONARR_URL/api/v3/customformat" -d "$cf_body" | jq -r '.id')
  echo "  created (id=$cf_id)"
else
  cf_id="$existing"
  echo "Custom format '$CF_NAME' already exists (id=$cf_id)"
fi

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

new_qp=$(jq \
  --argjson cf_id "$cf_id" \
  --arg cf_name "$CF_NAME" \
  --argjson score "$CF_SCORE" '
    .minFormatScore = 0
    | .formatItems = (
        [.formatItems[] | select(.format != $cf_id)]
        + [{format: $cf_id, name: $cf_name, score: $score}]
      )
  ' <<<"$qp")

call -X PUT "$SONARR_URL/api/v3/qualityprofile/$qp_id" -d "$new_qp" >/dev/null
echo "  minFormatScore=0; '$CF_NAME' score=$CF_SCORE"
echo ""
echo "Done."
echo "Next: delete the bad Daredevil files in Sonarr, then click 'Search Monitored'."
