#!/usr/bin/env bash
#
# One-shot prep for the xmpp1 sops-nix bootstrap.
#
# Collapses the fiddly parts of docs/xmpp.md into a single command. It creates
# the two encryption keys that secrets/xmpp1.yaml needs and writes them into
# .sops.yaml:
#
#   admin_cwage  - a standalone age key, so you can edit the secrets file later.
#                  Deliberately NOT derived from an existing SSH key: those are
#                  login credentials for other machines and get rotated, which
#                  would silently lock you out of your own secrets.
#   host_xmpp1   - xmpp1's SSH host key, so the box can decrypt its secrets at
#                  boot. Generated here rather than on the host so that sops can
#                  decrypt on the very first activation instead of needing a
#                  second deploy.
#
# It stops short of the two steps that involve actual secret values — writing
# secrets/xmpp1.yaml and running the installer — and prints those for you.
#
# Safe to re-run: it will not clobber an existing key or an already populated
# .sops.yaml.
#
# Usage:
#   scripts/bootstrap-xmpp1.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOPS_YAML="${REPO_ROOT}/.sops.yaml"
STAGE_DIR="/tmp/xmpp1-etc"
HOST_KEY="${STAGE_DIR}/etc/ssh/ssh_host_ed25519_key"
AGE_KEY_FILE="${HOME}/.config/sops/age/keys.txt"
# nix run needs flakes; they're off by default in the workstation nix.conf.
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v nix >/dev/null || die "nix not found on PATH"
[ -f "${SOPS_YAML}" ] || die "${SOPS_YAML} not found — run this from the homelab repo"

# No hardcoded IP default: it changes on every instance replacement, and a
# stale value here would put the wrong host into copy-pasteable install
# commands. Read it from tofu state, or take an explicit XMPP1_IP override.
if [ -z "${XMPP1_IP:-}" ]; then
    XMPP1_IP="$(cd "${REPO_ROOT}/tofu" && docker compose --env-file ../.env run --rm tofu tofu output -raw xmpp1_ip 2>/dev/null | tail -1)"
fi
[ -n "${XMPP1_IP}" ] || die "could not determine xmpp1's IP from tofu — pass it explicitly: XMPP1_IP=<ip> $0"

# --- 1. Your admin age key ---------------------------------------------------

if [ -s "${AGE_KEY_FILE}" ]; then
    echo "==> Reusing existing age key at ${AGE_KEY_FILE}"
else
    echo "==> Generating a standalone age key (first run downloads age, slow once)"
    mkdir -p "$(dirname "${AGE_KEY_FILE}")"
    nix shell nixpkgs#age --command age-keygen -o "${AGE_KEY_FILE}" 2>/dev/null
    chmod 600 "${AGE_KEY_FILE}"
    echo "==> Wrote ${AGE_KEY_FILE}"
fi

# The private half stays in the file and is never echoed. Only the public key,
# which is safe to print and to commit, is read back out.
ADMIN_AGE="$(grep '^# public key:' "${AGE_KEY_FILE}" | awk '{print $4}')"
[[ "${ADMIN_AGE}" == age1* ]] || die "could not read a public key from ${AGE_KEY_FILE}"

# --- 2. xmpp1's host key -----------------------------------------------------

if [ -f "${HOST_KEY}" ]; then
    echo "==> Host key already staged at ${HOST_KEY}, reusing"
else
    echo "==> Generating xmpp1 host key"
    mkdir -p "$(dirname "${HOST_KEY}")"
    ssh-keygen -t ed25519 -N "" -f "${HOST_KEY}" -C root@xmpp1 >/dev/null
fi

echo "==> Converting host key to age format"
HOST_AGE="$(nix run nixpkgs#ssh-to-age -- -i "${HOST_KEY}.pub")"
[[ "${HOST_AGE}" == age1* ]] || die "host age key looks wrong: ${HOST_AGE}"

# --- 3. Fill in .sops.yaml ---------------------------------------------------

if grep -q 'age1PLACEHOLDER' "${SOPS_YAML}"; then
    sed -i "s|age1PLACEHOLDER_REPLACE_WITH_CWAGE_ADMIN_AGE_PUBKEY|${ADMIN_AGE}|" "${SOPS_YAML}"
    sed -i "s|age1PLACEHOLDER_REPLACE_WITH_XMPP1_HOST_AGE_PUBKEY|${HOST_AGE}|" "${SOPS_YAML}"
    echo "==> Filled in ${SOPS_YAML}"
else
    echo "==> ${SOPS_YAML} has no placeholders left, not touching it"
fi

cat <<EOF

Done. Both encryption keys exist and .sops.yaml knows about them.

BACK UP ${AGE_KEY_FILE} — put a copy in Bitwarden next to the OpenBao root
token. It is the only way to decrypt secrets/xmpp1.yaml. Lose it and you have
to regenerate the values from OpenBao and re-encrypt from scratch.

Two steps left, both needing values this script deliberately does not touch.

1. Create the encrypted secrets file:

     export NIX_CONFIG='experimental-features = nix-command flakes'
     nix run nixpkgs#sops -- secrets/xmpp1.yaml

   Your editor opens on an empty file. Three keys (see secrets/README.md):

     cwage-password-hash: "<same value as kv/infra/users/cwage>"
     coturn-auth-secret: "<same value as kv/infra/coturn/auth>"
     acme-cloudflare-env: |
       CF_DNS_API_TOKEN=<zone-scoped cloudflare token>

   acme-cloudflare-env must be a KEY=value line, not a bare token — systemd
   reads it as an EnvironmentFile.

2. Install NixOS onto xmpp1. This wipes the Ubuntu image and reboots the box:

     git add secrets/xmpp1.yaml .sops.yaml
     nix run github:nix-community/nixos-anywhere -- --flake .#xmpp1 --extra-files ${STAGE_DIR} root@${XMPP1_IP}
     rm -rf ${STAGE_DIR}

   The git add matters — nix flakes only see git-tracked files.

Then, on xmpp1 itself:

     ssh -i ansible/keys/deploy deploy@${XMPP1_IP}
     sudo prosodyctl adduser cwage@quietlife.net
     sudo prosodyctl check
     sudo prosodyctl check dns

EOF
