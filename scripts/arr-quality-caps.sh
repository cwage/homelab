#!/usr/bin/env bash
# Cap Bluray/Remux 1080p quality definitions in Radarr & Sonarr so they stop
# grabbing 13-16GB Blu-ray encodes that are overkill for a streaming/Chromecast
# setup (and that choke on transcode / wifi).
#
# WHY THIS EXISTS: the default *arr quality definitions cap WEB/HDTV tiers
# (~100-130 MB/min) but leave Bluray and Remux UNCAPPED (maxSize=null). That's
# why huge Bluray-1080p releases (~115-130 MB/min, 13-16GB/movie) get grabbed.
# This sets a sane MB/min ceiling on just those tiers. Idempotent.
#
# Pulls each app's API key from /config/config.xml inside the running container
# over SSH -- no need to copy it from the UI. SSHes as your user (in the docker
# group on containers), not deploy.
#
# Companion to scripts/radarr-english-only.sh / scripts/sonarr-english-only.sh
# (those handle language + disallowing Remux; this handles file size).
#
# Usage:
#   scripts/arr-quality-caps.sh
#
# Overrides:
#   SSH_HOST=cwage@containers.lan.quietlife.net   (default)
#   RADARR_URL=https://radarr.lan.quietlife.net   (default)
#   SONARR_URL=https://sonarr.lan.quietlife.net   (default)
#   MAX_MBMIN=70    # hard ceiling, MB per minute  (~9GB for a 2h movie)
#   PREF_MBMIN=50   # preferred target, MB per minute
#
# Requires: ssh, curl, jq

set -euo pipefail

SSH_HOST="${SSH_HOST:-cwage@containers.lan.quietlife.net}"
RADARR_URL="${RADARR_URL:-https://radarr.lan.quietlife.net}"
SONARR_URL="${SONARR_URL:-https://sonarr.lan.quietlife.net}"
MAX_MBMIN="${MAX_MBMIN:-70}"
PREF_MBMIN="${PREF_MBMIN:-50}"

# Matches Bluray-1080p, "Bluray-1080p Remux", Remux-1080p, etc. -- the tiers
# that ship uncapped. WEB/HDTV tiers are left alone (already capped sanely).
QUALITY_REGEX='(Bluray|Remux).*1080p|1080p.*(Bluray|Remux)'

cap_app() {
  local name="$1" url="$2" container="$3"
  echo "== ${name} =="

  local key
  key=$(ssh -o BatchMode=yes "$SSH_HOST" "docker exec ${container} cat /config/config.xml" \
    | sed -n 's|.*<ApiKey>\(.*\)</ApiKey>.*|\1|p')
  [[ -n "$key" ]] || { echo "  ERROR: could not read ${container} API key"; return 1; }

  local defs
  defs=$(curl -fsS -H "X-Api-Key: $key" "${url}/api/v3/qualitydefinition")

  # Emit one compact JSON object per matching definition. Iterate by id so
  # quality names containing spaces (e.g. "Bluray-1080p Remux") are safe.
  local matched=0
  while IFS= read -r def; do
    [[ -n "$def" ]] || continue
    matched=1
    local qn id body
    qn=$(jq -r '.quality.name' <<<"$def")
    id=$(jq -r '.id' <<<"$def")
    body=$(jq -c --argjson mx "$MAX_MBMIN" --argjson pf "$PREF_MBMIN" \
      '.maxSize = $mx | .preferredSize = (if .minSize > $pf then .minSize else $pf end)' <<<"$def")
    curl -fsS -X PUT -H "X-Api-Key: $key" -H "Content-Type: application/json" \
      "${url}/api/v3/qualitydefinition/${id}" -d "$body" >/dev/null \
      && echo "  ${qn} -> pref=${PREF_MBMIN} max=${MAX_MBMIN} MB/min"
  done < <(jq -c --arg re "$QUALITY_REGEX" '.[] | select(.quality.name | test($re))' <<<"$defs")

  [[ "$matched" -eq 1 ]] || echo "  (no matching quality definitions found)"
}

cap_app Radarr "$RADARR_URL" radarr
cap_app Sonarr "$SONARR_URL" sonarr

echo ""
echo "Done. Caps apply to future grabs and upgrades; already-downloaded"
echo "oversized files are left in place (delete + re-search to replace them)."
