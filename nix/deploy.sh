#!/usr/bin/env bash
# Deploy a NixOS configuration to a remote host.
# Runs inside the Nix container via: make nix-deploy-host HOST=<name>
#
# Builds the NixOS config locally, copies store paths to the target via
# nix copy, shows what would change, dry-runs the activation, and then asks
# before switching. Set CONFIRM=no to skip the prompt (or pass NOCONFIRM=1 to
# make). Requires the target to have trusted-users = [ "root" "deploy" ] in
# its nix config (baked into the template via base.nix).
#
# Rollback: every switch leaves the previous generation bootable. On the host,
# `sudo nixos-rebuild switch --rollback` (or pick it from the boot menu).

set -euo pipefail

HOST="${1:?Usage: deploy.sh <host>}"

SSH_KEY="/root/.ssh/deploy"
SSH_USER="deploy"
TARGET="${DEPLOY_TARGET:-${HOST}}"
CONFIRM="${CONFIRM:-yes}"

export NIX_SSHOPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=accept-new"
remote() { ssh ${NIX_SSHOPTS} "${SSH_USER}@${TARGET}" "$@"; }

echo "Building NixOS configuration '${HOST}'..."
SYSTEM_PATH=$(nix build "/workspace#nixosConfigurations.${HOST}.config.system.build.toplevel" \
    --print-out-paths --no-link)

echo "Copying store paths to ${SSH_USER}@${TARGET}..."
nix copy --to "ssh://${SSH_USER}@${TARGET}" "${SYSTEM_PATH}"

CURRENT=$(remote readlink -f /run/current-system)
if [ "${CURRENT}" = "${SYSTEM_PATH}" ]; then
    echo "${TARGET} is already running ${SYSTEM_PATH}; nothing to do."
    exit 0
fi

echo ""
echo "=== Package changes (current -> new) ==="
remote nix store diff-closures /run/current-system "${SYSTEM_PATH}"

echo ""
echo "=== Activation dry run (units that would restart/reload/start/stop) ==="
remote "sudo -n ${SYSTEM_PATH}/bin/switch-to-configuration dry-activate"

if [ "${CONFIRM}" != "no" ]; then
    echo ""
    read -r -p "Switch ${TARGET} to the new configuration? [y/N] " answer
    case "${answer}" in
        y|Y|yes|YES) ;;
        *) echo "Aborted; nothing changed on ${TARGET}."; exit 1 ;;
    esac
fi

echo "Activating configuration on ${TARGET}..."
remote "sudo -n nix-env -p /nix/var/nix/profiles/system --set ${SYSTEM_PATH} && sudo -n ${SYSTEM_PATH}/bin/switch-to-configuration switch"

echo "Deploy complete: ${HOST} -> ${TARGET} (${SYSTEM_PATH})"
