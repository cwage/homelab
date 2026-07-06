#!/bin/sh
# break-glass-drill.sh — quarterly break-glass restore drill (issue #174 §3)
#
# Proves the credentials written in the break-glass store (Bitwarden / the
# #213 USB) can actually decrypt the off-site B2 backups, using NOTHING from
# the homelab: no OpenBao, no existing rclone config, no NAS. This is the
# only test that catches a wrong/stale crypt password or salt — with those
# wrong, every byte on B2 is unrecoverable noise and no other check notices.
#
# Usage: ./break-glass-drill.sh   (any machine with Docker; ~15 minutes)
#
# The script re-executes itself inside a throwaway rclone container.
# Credentials are typed at hidden prompts inside the container and exist
# only in its memory; nothing is written to disk, docker inspect, or shell
# history. The container is removed on exit (--rm).
#
# Read out of the break-glass store before starting (names match the
# openbao-agent template files used by the production backup jobs):
#   - b2-account   B2 application key ID
#   - b2-key       B2 application key
#   - b2crypt-pw   rclone crypt password (note whether it is stored as the
#                  rclone-obscured string or as plaintext — the drill asks)
#   - b2crypt-pw2  crypt salt, ONLY if one was configured (most setups: no)

set -eu

RCLONE_IMAGE="rclone/rclone:1.68"

if [ -z "${DRILL_INNER:-}" ]; then
    # Outer half: relaunch inside the clean-room container. The script is
    # mounted read-only; no credentials are passed from the host.
    exec docker run --rm -it --pull=missing \
        -e DRILL_INNER=1 \
        -v "$(readlink -f "$0")":/drill.sh:ro \
        --entrypoint /bin/sh \
        "$RCLONE_IMAGE" /drill.sh
fi

# ---------------------------------------------------------------------------
# Inner half: runs inside the container (busybox sh — keep it POSIX).
# ---------------------------------------------------------------------------

BUCKET_DEFAULT="cwagenas-backup"

prompt() {
    # prompt <message> [hidden]  — reads a line into $REPLY
    printf '%s: ' "$1" >&2
    if [ "${2:-}" = "hidden" ]; then
        stty -echo
        read -r REPLY
        stty echo
        printf '\n' >&2
    else
        read -r REPLY
    fi
}

echo ""
echo "=== Break-glass restore drill ==="
echo "Use ONLY values read from the break-glass store (Bitwarden / USB)."
echo "Do NOT copy them from OpenBao or a working machine — the point is to"
echo "prove the written-down set is sufficient on its own."
echo ""

prompt "B2 application key ID (b2-account)"
B2_ACCOUNT="$REPLY"
prompt "B2 application key (b2-key)" hidden
B2_KEY="$REPLY"
prompt "Bucket [$BUCKET_DEFAULT]"
BUCKET="${REPLY:-$BUCKET_DEFAULT}"

prompt "Is the crypt password stored as the rclone-OBSCURED string (as OpenBao holds it) or PLAINTEXT? [obscured/plain]"
PW_FORM="$REPLY"
prompt "Crypt password (b2crypt-pw)" hidden
CRYPT_PW="$REPLY"
if [ "$PW_FORM" = "plain" ] || [ "$PW_FORM" = "plaintext" ]; then
    CRYPT_PW=$(rclone obscure "$CRYPT_PW")
fi

prompt "Crypt salt (b2crypt-pw2) — press Enter if none is configured" hidden
CRYPT_PW2="$REPLY"

# Same env-var remote construction as the production backup-b2 job — no
# config file, and defaults for everything else (standard filename
# encryption), which is exactly what production uses.
export RCLONE_CONFIG_BGB2_TYPE=b2
export RCLONE_CONFIG_BGB2_ACCOUNT="$B2_ACCOUNT"
export RCLONE_CONFIG_BGB2_KEY="$B2_KEY"
export RCLONE_CONFIG_BGCRYPT_TYPE=crypt
export RCLONE_CONFIG_BGCRYPT_REMOTE="bgb2:$BUCKET"
export RCLONE_CONFIG_BGCRYPT_PASSWORD="$CRYPT_PW"
if [ -n "$CRYPT_PW2" ]; then
    export RCLONE_CONFIG_BGCRYPT_PASSWORD2="$CRYPT_PW2"
fi

# Deliberately no pipes on the rclone checks: busybox sh has no pipefail,
# and `rclone ... | head` would hide a failed rclone behind head's exit 0.
echo ""
echo "--- Step 1/4: B2 authentication (raw bucket listing) ---"
echo "Failure here means the B2 account/key pair is wrong or lacks access."
rclone lsd "bgb2:$BUCKET" --max-depth 1 > /tmp/step1.out
head -5 /tmp/step1.out
echo "PASS: B2 credentials authenticate and the bucket is readable."

echo ""
echo "--- Step 2/4: crypt layer (decrypted top-level listing) ---"
echo "Failure or garbage names here means the crypt password/salt is wrong."
rclone lsd "bgcrypt:" > /tmp/step2.out
head -20 /tmp/step2.out
echo "PASS if the share names above are readable (Pictures, Documents, ...)."

echo ""
echo "--- Step 3/4: file listing inside a share ---"
prompt "Share to sample [Documents]"
SHARE="${REPLY:-Documents}"
rclone lsf --files-only --recursive "bgcrypt:$SHARE" > /tmp/step3.out
head -20 /tmp/step3.out
echo "(first 20 of $(wc -l < /tmp/step3.out) files shown)"

echo ""
echo "--- Step 4/4: download + checksum a sample file ---"
prompt "Paste one file path from the listing above"
SAMPLE="$REPLY"
rclone copyto "bgcrypt:$SHARE/$SAMPLE" /tmp/drill-sample
echo ""
ls -l /tmp/drill-sample
sha256sum /tmp/drill-sample
echo ""
echo "Compare that hash against the live source from your workstation:"
echo "  ssh -i ansible/keys/deploy deploy@10.10.15.11 sha256sum \"/mnt/nas/$SHARE/$SAMPLE\""
echo "(A mismatch is only meaningful if the file hasn't changed since the"
echo " last nightly sync — prefer sampling something old and stable.)"
echo ""
echo "=== Drill complete ==="
echo "If all four steps passed: record the result in issue #174 and confirm"
echo "these exact values are in the break-glass store (#213). If the crypt"
echo "password needed the plain/obscured answer to work, write WHICH form"
echo "the store holds next to the entry — future-you under stress will not"
echo "remember."
