#!/bin/bash
set -uo pipefail

# backup.sh — Unified backup script for NAS shares
#
# Supports multiple backup targets via --target flag:
#   b2     — Backblaze B2 (encrypted via rclone crypt)
#   local  — Local USB drive (plain rsync via rclone)
#
# Target name maps to:
#   - Targets file: targets/<target>.txt
#   - Lock file:    /tmp/backup-<target>.lock
#   - Log file:     <target>-YYYYMMDD-HHMMSS.log
#
# Usage:
#   backup.sh --target b2                  # quiet mode (for cron)
#   backup.sh --target local --interactive # show rclone progress
#   backup.sh --target b2 --dry-run       # rclone dry-run, no changes
#   backup.sh --target local --interactive --dry-run  # both

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine base directory for backup configuration.
# Use BACKUP_BASE_DIR env var if set, otherwise derive from script location
# with a fallback to /opt/backup (handles Dockerfile COPY flattening).
CANDIDATE_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -n "${BACKUP_BASE_DIR:-}" ]]; then
    BASE_DIR="$BACKUP_BASE_DIR"
elif [[ -d "$CANDIDATE_BASE_DIR/targets" ]]; then
    BASE_DIR="$CANDIDATE_BASE_DIR"
else
    BASE_DIR="/opt/backup"
fi

NAS_ROOT="/mnt/nas"
LOG_DIR="/var/log/backup"

TARGET=""
INTERACTIVE=false
DRY_RUN=false
LOG_LEVEL="INFO"
START_TIME=$(date +%s)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --target=*)       TARGET="${arg#--target=}" ;;
        --interactive|-i) INTERACTIVE=true ;;
        --dry-run|-n)     DRY_RUN=true ;;
        --log-level=*)    LOG_LEVEL="${arg#--log-level=}" ;;
        --help|-h)
            echo "Usage: $(basename "$0") --target <name> [--interactive|-i] [--dry-run|-n] [--log-level=LEVEL]"
            echo ""
            echo "  --target <name>         Backup target (required): b2, local"
            echo "  --interactive, -i       Show rclone transfer progress"
            echo "  --dry-run, -n           Pass --dry-run to rclone (no changes made)"
            echo "  --log-level=LEVEL       Set rclone log level (DEBUG|INFO|NOTICE|ERROR)"
            echo ""
            echo "Targets:"
            echo "  b2      Sync to Backblaze B2 (encrypted via rclone crypt)"
            echo "  local   Sync to local USB drive (/backup/local)"
            exit 0
            ;;
        *)
            # Support --target b2 (space-separated) by capturing next positional
            if [[ "$arg" == "--target" ]]; then
                # handled below
                :
            elif [[ "${PREV_ARG:-}" == "--target" ]]; then
                TARGET="$arg"
            else
                echo "Unknown option: $arg" >&2
                exit 1
            fi
            ;;
    esac
    PREV_ARG="$arg"
done

if [[ -z "$TARGET" ]]; then
    echo "ERROR: --target is required. Use --help for usage." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Target configuration
# ---------------------------------------------------------------------------
TARGETS_FILE="${BASE_DIR}/targets/${TARGET}.txt"
LOCK_FILE="/tmp/backup-${TARGET}.lock"

# Map target name to rclone destination
case "$TARGET" in
    b2)
        REMOTE="b2crypt"
        dest_prefix=""
        ;;
    local)
        REMOTE="/backup/local"
        dest_prefix=""
        ;;
    *)
        echo "ERROR: Unknown target '$TARGET'. Valid targets: b2, local" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE=""
mkdir -p "$LOG_DIR" 2>/dev/null
if [[ -w "$LOG_DIR" ]]; then
    LOG_FILE="${LOG_DIR}/${TARGET}-$(date +%Y%m%d-%H%M%S).log"
fi

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$msg" >> "$LOG_FILE"
    fi
    if $INTERACTIVE || [[ -z "$LOG_FILE" ]]; then
        echo "$msg"
    fi
}

# ---------------------------------------------------------------------------
# Notifications (ntfy.sh)
# ---------------------------------------------------------------------------
ntfy_send() {
    local priority="$1" title="$2" body="$3" tags="${4:-}"
    [[ -z "${NTFY_TOPIC:-}" ]] && return 0
    # Strip control characters from body for defense in depth
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
# Locking (flock-based — prevents overlapping runs per target)
# ---------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Another backup instance for target '$TARGET' is already running (lock: $LOCK_FILE)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ ! -f "$TARGETS_FILE" ]]; then
    echo "ERROR: targets file not found: $TARGETS_FILE" >&2
    exit 1
fi

if ! command -v rclone &>/dev/null; then
    echo "ERROR: rclone not found in PATH" >&2
    exit 1
fi

# For local target, verify the USB drive is mounted
if [[ "$TARGET" == "local" ]]; then
    if ! mountpoint -q /backup/local 2>/dev/null && [[ ! "$(ls -A /backup/local 2>/dev/null)" ]]; then
        MSG="Local backup target /backup/local is not mounted or empty — aborting"
        echo "ERROR: $MSG" >&2
        ntfy_send urgent "Backup FAILED" "$MSG" "x"
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Read paths (skip comments and blank lines)
# ---------------------------------------------------------------------------
mapfile -t PATHS < <(grep -v '^[[:space:]]*#' "$TARGETS_FILE" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#PATHS[@]} -eq 0 ]]; then
    log "No paths enabled in $TARGETS_FILE — nothing to do."
    exit 0
fi

log "Starting $TARGET backup — ${#PATHS[@]} path(s) to sync"
if $DRY_RUN; then
    log "DRY RUN — no changes will be made"
fi

# ---------------------------------------------------------------------------
# Build rclone flags
# ---------------------------------------------------------------------------
RCLONE_FLAGS=(
    --log-level "$LOG_LEVEL"
    --exclude "@eaDir/**"
    --exclude "#recycle/**"
    --exclude "*.db-wal"
    --exclude "*.db-shm"
    --exclude "*/logs/**"
)

if [[ -n "$LOG_FILE" ]]; then
    RCLONE_FLAGS+=(--log-file "$LOG_FILE")
fi

if $INTERACTIVE; then
    RCLONE_FLAGS+=(--progress)
fi

if $DRY_RUN; then
    RCLONE_FLAGS+=(--dry-run)
fi

# ---------------------------------------------------------------------------
# Sync each path
# ---------------------------------------------------------------------------
FAILED=()
SUCCEEDED=()

for path in "${PATHS[@]}"; do
    src="${NAS_ROOT}/${path}"

    if [[ ! -d "$src" ]]; then
        log "WARNING: source directory does not exist, skipping: $src"
        FAILED+=("$path (not found)")
        continue
    fi

    # Build destination based on target type
    case "$TARGET" in
        b2)    dest="${REMOTE}:${path}" ;;
        local) dest="${REMOTE}/${path}" ;;
    esac

    log "Syncing: $src -> $dest"
    if rclone sync "$src" "$dest" "${RCLONE_FLAGS[@]}"; then
        log "OK: $path"
        SUCCEEDED+=("$path")
    else
        log "FAILED: $path (rclone exit code $?)"
        FAILED+=("$path")
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
DURATION=$(format_duration $(( $(date +%s) - START_TIME )))
TARGET_UPPER=$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')

log "---"
log "Backup complete ($TARGET_UPPER): ${#SUCCEEDED[@]} succeeded, ${#FAILED[@]} failed (${DURATION})"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "Failed paths:"
    for p in "${FAILED[@]}"; do
        log "  - $p"
    done
    FAIL_LIST=$(printf '%s, ' "${FAILED[@]}")
    ntfy_send urgent "Backup FAILED ($TARGET_UPPER)" \
        "${#FAILED[@]}/${#PATHS[@]} paths failed (${DURATION}): ${FAIL_LIST%, }" \
        "x"
    exit 1
fi

if ! $DRY_RUN; then
    ntfy_send default "Backup completed ($TARGET_UPPER)" \
        "${#SUCCEEDED[@]} paths synced in ${DURATION}" \
        "white_check_mark"
fi

exit 0
