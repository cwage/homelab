#!/bin/bash
set -uo pipefail

# backup-configs.sh — Snapshot named docker volumes for the containers stack
# to NFS share at /mnt/nas/containers-configs.
#
# For each service, this:
#   1. Stops the compose service (so on-disk state is consistent)
#   2. rsyncs the volume into /mnt/nas/containers-configs/<service>/
#      via an ephemeral alpine+rsync container (volume is root-owned)
#   3. Starts the service back up
#
# Run on the containers VM, NOT inside the backup container — this needs
# host-level docker access. Bind mounts under /mnt/nas/ are not backed up
# (they already live on the NAS). jellyfin_cache is skipped (regenerable).
#
# Usage:
#   backup-configs.sh [--dry-run]
#
# Run via Ansible: make ansible-backup-configs

COMPOSE_DIR="${COMPOSE_DIR:-/opt/stacks}"
DEST_ROOT="${DEST_ROOT:-/mnt/nas/containers-configs}"
LOG_DIR="${LOG_DIR:-/var/log/backup}"
ENV_FILE="${ENV_FILE:-/opt/backup/.env}"
LOCK_FILE="${LOCK_FILE:-/tmp/backup-configs.lock}"
RSYNC_IMAGE="${RSYNC_IMAGE:-alpine:3.20}"

DRY_RUN=false
START_TIME=$(date +%s)

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=true ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--dry-run|-n]"
            echo
            echo "Snapshots named docker volumes for the containers stack to"
            echo "  ${DEST_ROOT}/<service>/"
            echo
            echo "Each service is stopped, rsynced, then started."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

# service:mount-destination pairs. Volume names are resolved at runtime by
# inspecting the container, so this works regardless of compose project prefix
# (e.g., volumes are named `stacks_jellyfin_config`, not `jellyfin_config`).
# Bind mounts under /mnt/nas/ are skipped (already on NAS). jellyfin_cache is
# skipped (regenerable from media library).
SERVICES=(
    "jellyfin:/config"
    "sabnzbd:/config"
    "radarr:/config"
    "sonarr:/config"
    "paperless-redis:/data"
)

# Source env file for NTFY_TOPIC (best-effort)
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR" 2>/dev/null
LOG_FILE=""
if [[ -w "$LOG_DIR" ]]; then
    LOG_FILE="${LOG_DIR}/backup-configs-$(date +%Y%m%d-%H%M%S).log"
fi

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

# ---------------------------------------------------------------------------
# Notifications (ntfy.sh) — mirrors backup.sh
# ---------------------------------------------------------------------------
ntfy_send() {
    local priority="$1" title="$2" body="$3" tags="${4:-}"
    [[ -z "${NTFY_TOPIC:-}" ]] && return 0
    local sanitized_body
    sanitized_body=$(printf '%s' "$body" | tr -d '[:cntrl:]') || sanitized_body=""
    local -a curl_args=(-sf -o /dev/null)
    [[ -n "$priority" ]] && curl_args+=(-H "Priority: ${priority}")
    [[ -n "$title" ]]    && curl_args+=(-H "Title: ${title}")
    [[ -n "$tags" ]]     && curl_args+=(-H "Tags: ${tags}")
    curl "${curl_args[@]}" -d "${sanitized_body}" "${NTFY_TOPIC}" || true
}

format_duration() {
    local secs=$1
    if (( secs >= 3600 )); then
        printf '%dh %dm %ds' $((secs/3600)) $((secs%3600/60)) $((secs%60))
    elif (( secs >= 60 )); then
        printf '%dm %ds' $((secs/60)) $((secs%60))
    else
        printf '%ds' "$secs"
    fi
}

# ---------------------------------------------------------------------------
# Locking
# ---------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Another backup-configs run is in progress (lock: $LOCK_FILE)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    log "ERROR: docker not in PATH"
    exit 1
fi

if [[ ! -f "$COMPOSE_DIR/docker-compose.yml" ]]; then
    log "ERROR: compose file not found: $COMPOSE_DIR/docker-compose.yml"
    ntfy_send urgent "Config backup FAILED" "Compose file missing: $COMPOSE_DIR" "x"
    exit 1
fi

if ! mountpoint -q "$DEST_ROOT" 2>/dev/null; then
    log "ERROR: $DEST_ROOT is not a mount point — refusing to write to local fs"
    ntfy_send urgent "Config backup FAILED" "NFS dest not mounted: $DEST_ROOT" "x"
    exit 1
fi

if ! touch "$DEST_ROOT/.backup-configs-write-test" 2>/dev/null; then
    log "ERROR: $DEST_ROOT is not writable"
    ntfy_send urgent "Config backup FAILED" "Dest not writable: $DEST_ROOT" "x"
    exit 1
fi
rm -f "$DEST_ROOT/.backup-configs-write-test"

log "Starting config backup — ${#SERVICES[@]} service(s) to snapshot"
$DRY_RUN && log "DRY RUN — will not stop services or write files"

# ---------------------------------------------------------------------------
# Sync each service
# ---------------------------------------------------------------------------
SUCCEEDED=()
FAILED=()

for entry in "${SERVICES[@]}"; do
    svc="${entry%%:*}"
    mount_dest="${entry##*:}"
    dest="$DEST_ROOT/$svc"

    log "---"
    log "Service: $svc  (mount: $mount_dest)"

    # Resolve the actual docker volume backing this service's mount.
    # Use `compose ps -q` so we don't depend on container_name conventions.
    container_id=$(docker compose -f "$COMPOSE_DIR/docker-compose.yml" ps -q "$svc" 2>/dev/null)
    if [[ -z "$container_id" ]]; then
        log "  ERROR: no running container for service '$svc'"
        FAILED+=("$svc (container not running)")
        continue
    fi

    vol=$(docker inspect "$container_id" --format \
        "{{range .Mounts}}{{if and (eq .Type \"volume\") (eq .Destination \"$mount_dest\")}}{{.Name}}{{end}}{{end}}" 2>/dev/null)
    if [[ -z "$vol" ]]; then
        log "  ERROR: no named volume mounted at '$mount_dest' in $svc"
        FAILED+=("$svc (volume lookup failed)")
        continue
    fi
    log "  Resolved volume: $vol"

    if $DRY_RUN; then
        log "  [dry-run] would stop $svc, sync $vol -> $dest, start $svc"
        SUCCEEDED+=("$svc (dry-run)")
        continue
    fi

    mkdir -p "$dest"

    log "  Stopping $svc..."
    if ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" stop "$svc"; then
        log "  ERROR: failed to stop $svc, skipping"
        FAILED+=("$svc (stop failed)")
        continue
    fi

    log "  Syncing $vol -> $dest ..."
    if docker run --rm \
        -v "${vol}:/src:ro" \
        -v "${dest}:/dst" \
        "$RSYNC_IMAGE" \
        sh -c 'apk add --no-cache -q rsync >/dev/null && rsync -aHAX --delete /src/ /dst/'; then
        log "  OK: $svc"
        SUCCEEDED+=("$svc")
    else
        log "  ERROR: rsync failed for $svc"
        FAILED+=("$svc (rsync failed)")
    fi

    log "  Starting $svc..."
    if ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" start "$svc"; then
        log "  ERROR: failed to start $svc — manual intervention may be required"
        FAILED+=("$svc (start failed — service may be down)")
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
DURATION=$(format_duration $(( $(date +%s) - START_TIME )))
log "---"
log "Config backup complete: ${#SUCCEEDED[@]} succeeded, ${#FAILED[@]} failed (${DURATION})"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "Failed:"
    for f in "${FAILED[@]}"; do
        log "  - $f"
    done
    FAIL_LIST=$(printf '%s, ' "${FAILED[@]}")
    ntfy_send urgent "Config backup FAILED" \
        "${#FAILED[@]}/${#SERVICES[@]} failed (${DURATION}): ${FAIL_LIST%, }" \
        "x"
    exit 1
fi

if ! $DRY_RUN; then
    ntfy_send default "Config backup completed" \
        "${#SUCCEEDED[@]} services snapshotted in ${DURATION}" \
        "white_check_mark"
fi

exit 0
