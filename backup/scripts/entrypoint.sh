#!/bin/bash
set -euo pipefail

# Backup container entrypoint
# Fetches secrets from OpenBao and exports as rclone environment variables
# Falls back to .env if OpenBao is unavailable or credentials already set

BAO_BACKUP_SECRET_PATH="${BAO_BACKUP_SECRET_PATH:-kv/data/backup/backblaze}"
BAO_CRYPT_SECRET_PATH="${BAO_CRYPT_SECRET_PATH:-kv/data/backup/rclone-crypt}"

fetch_from_openbao() {
    local path="$1"
    local field="$2"

    if [[ -z "${BAO_ADDR:-}" ]] || [[ -z "${BAO_TOKEN:-}" ]]; then
        return 1
    fi

    local curl_opts=(-sf -H "X-Vault-Token: ${BAO_TOKEN}")
    if [[ "${BAO_SKIP_VERIFY:-}" == "true" ]]; then
        curl_opts+=(--insecure)
    fi

    curl "${curl_opts[@]}" "${BAO_ADDR}/v1/${path}" | jq -r ".data.data.${field} // empty"
}

setup_rclone_config() {
    # B2 credentials
    if [[ -z "${RCLONE_CONFIG_B2_ACCOUNT:-}" ]]; then
        echo "Fetching B2 credentials from OpenBao..."
        export RCLONE_CONFIG_B2_TYPE="b2"
        export RCLONE_CONFIG_B2_ACCOUNT="$(fetch_from_openbao "$BAO_BACKUP_SECRET_PATH" "account_id")"
        export RCLONE_CONFIG_B2_KEY="$(fetch_from_openbao "$BAO_BACKUP_SECRET_PATH" "application_key")"

        if [[ -z "${RCLONE_CONFIG_B2_ACCOUNT:-}" ]]; then
            echo "WARNING: Could not fetch B2 credentials from OpenBao"
            echo "         Set RCLONE_CONFIG_B2_* env vars in .env as fallback"
        else
            echo "B2 credentials loaded from OpenBao"
        fi
    else
        echo "B2 credentials loaded from environment"
    fi

    # Crypt overlay credentials
    if [[ -z "${RCLONE_CONFIG_B2CRYPT_PASSWORD:-}" ]]; then
        echo "Fetching crypt credentials from OpenBao..."
        export RCLONE_CONFIG_B2CRYPT_TYPE="crypt"
        export RCLONE_CONFIG_B2CRYPT_REMOTE="${RCLONE_CONFIG_B2CRYPT_REMOTE:-b2:cwagenas-backup}"
        export RCLONE_CONFIG_B2CRYPT_PASSWORD="$(fetch_from_openbao "$BAO_CRYPT_SECRET_PATH" "password")"
        export RCLONE_CONFIG_B2CRYPT_PASSWORD2="$(fetch_from_openbao "$BAO_CRYPT_SECRET_PATH" "password2")"

        if [[ -z "${RCLONE_CONFIG_B2CRYPT_PASSWORD:-}" ]]; then
            echo "WARNING: Could not fetch crypt credentials from OpenBao"
            echo "         Set RCLONE_CONFIG_B2CRYPT_* env vars in .env as fallback"
        else
            echo "Crypt credentials loaded from OpenBao"
        fi
    else
        echo "Crypt credentials loaded from environment"
    fi
}

status_msg() {
    if [[ -n "${1:-}" ]]; then
        echo "configured"
    else
        echo "${2:-NOT SET}"
    fi
}

show_rclone_status() {
    echo ""
    echo "rclone configuration status:"
    echo "  B2 account:     $(status_msg "${RCLONE_CONFIG_B2_ACCOUNT:-}")"
    echo "  B2 key:         $(status_msg "${RCLONE_CONFIG_B2_KEY:-}")"
    echo "  Crypt remote:   ${RCLONE_CONFIG_B2CRYPT_REMOTE:-NOT SET}"
    echo "  Crypt password: $(status_msg "${RCLONE_CONFIG_B2CRYPT_PASSWORD:-}")"
    echo "  Crypt salt:     $(status_msg "${RCLONE_CONFIG_B2CRYPT_PASSWORD2:-}" "not set (optional)")"
    echo ""
    echo "Available rclone remotes (if configured):"
    echo "  b2:        - Raw Backblaze B2 bucket"
    echo "  b2crypt:   - Encrypted overlay on B2"
    echo ""
}

main() {
    echo "=== Backup container starting ==="
    setup_rclone_config
    show_rclone_status

    # Execute the command passed to the container
    exec "$@"
}

main "$@"
