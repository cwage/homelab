#!/bin/bash
set -uo pipefail

# backup-remote.sh — Sync NAS shares to Backblaze B2 (encrypted via rclone crypt)
#
# Reads paths from paths/remote.txt (one share name per line, relative to /mnt/nas)
# and syncs each to the b2crypt: remote.
#
# Usage:
#   backup-remote.sh                  # quiet mode (for cron)
#   backup-remote.sh --interactive    # show rclone progress
#   backup-remote.sh --dry-run        # rclone dry-run, no changes
#   backup-remote.sh --interactive --dry-run  # both

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine base directory for backup configuration.
# Use BACKUP_BASE_DIR env var if set, otherwise derive from script location
# with a fallback to /opt/backup (handles Dockerfile COPY flattening).
CANDIDATE_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ -n "${BACKUP_BASE_DIR:-}" ]]; then
    BASE_DIR="$BACKUP_BASE_DIR"
elif [[ -d "$CANDIDATE_BASE_DIR/paths" ]]; then
    BASE_DIR="$CANDIDATE_BASE_DIR"
else
    BASE_DIR="/opt/backup"
fi

PATHS_FILE="${BACKUP_PATHS_FILE:-"$BASE_DIR/paths/remote.txt"}"
NAS_ROOT="/mnt/nas"
REMOTE="b2crypt"
LOG_DIR="/var/log/backup"
LOCK_FILE="/tmp/backup-remote.lock"

INTERACTIVE=false
DRY_RUN=false
LOG_LEVEL="INFO"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case "$arg" in
        --interactive|-i) INTERACTIVE=true ;;
        --dry-run|-n)     DRY_RUN=true ;;
        --log-level=*)    LOG_LEVEL="${arg#--log-level=}" ;;
        --help|-h)
            echo "Usage: $(basename "$0") [--interactive|-i] [--dry-run|-n] [--log-level=LEVEL]"
            echo ""
            echo "  --interactive, -i       Show rclone transfer progress"
            echo "  --dry-run, -n           Pass --dry-run to rclone (no changes made)"
            echo "  --log-level=LEVEL       Set rclone log level (DEBUG|INFO|NOTICE|ERROR)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
LOG_FILE=""
mkdir -p "$LOG_DIR" 2>/dev/null
if [[ -w "$LOG_DIR" ]]; then
    LOG_FILE="${LOG_DIR}/remote-$(date +%Y%m%d-%H%M%S).log"
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
# Locking (flock-based — prevents overlapping runs)
# ---------------------------------------------------------------------------
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "Another backup-remote instance is already running (lock: $LOCK_FILE)" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ ! -f "$PATHS_FILE" ]]; then
    echo "ERROR: paths file not found: $PATHS_FILE" >&2
    exit 1
fi

if ! command -v rclone &>/dev/null; then
    echo "ERROR: rclone not found in PATH" >&2
    exit 1
fi

# Verify rclone can reach the remote (checks credentials)
if ! rclone lsd "${REMOTE}:" --max-depth 0 &>/dev/null; then
    echo "ERROR: cannot list ${REMOTE}: — check rclone credentials" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Read paths (skip comments and blank lines)
# ---------------------------------------------------------------------------
mapfile -t PATHS < <(grep -v '^[[:space:]]*#' "$PATHS_FILE" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [[ ${#PATHS[@]} -eq 0 ]]; then
    log "No paths enabled in $PATHS_FILE — nothing to do."
    exit 0
fi

log "Starting remote backup — ${#PATHS[@]} path(s) to sync"
if $DRY_RUN; then
    log "DRY RUN — no changes will be made"
fi

# ---------------------------------------------------------------------------
# Build rclone flags
# ---------------------------------------------------------------------------
RCLONE_FLAGS=(
    --log-level "$LOG_LEVEL"
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

    log "Syncing: $src -> ${REMOTE}:${path}"
    if rclone sync "$src" "${REMOTE}:${path}" "${RCLONE_FLAGS[@]}"; then
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
log "---"
log "Backup complete: ${#SUCCEEDED[@]} succeeded, ${#FAILED[@]} failed"

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "Failed paths:"
    for p in "${FAILED[@]}"; do
        log "  - $p"
    done
    exit 1
fi

exit 0
