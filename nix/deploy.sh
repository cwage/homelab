#!/usr/bin/env bash
# Deploy a NixOS configuration to a remote host.
# Runs inside the Nix container via: make nix-deploy-host HOST=<name>
#
# Builds the NixOS config locally, copies store paths to the target via
# nix copy, then activates the new configuration over SSH.
# Requires the target to have trusted-users = [ "root" "deploy" ] in
# its nix config (baked into the template via base.nix).

set -euo pipefail

HOST="${1:?Usage: deploy.sh <host>}"

SSH_KEY="/root/.ssh/deploy"
SSH_USER="deploy"
TARGET="${DEPLOY_TARGET:-${HOST}}"

export NIX_SSHOPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=accept-new"

echo "Building NixOS configuration '${HOST}'..."
SYSTEM_PATH=$(nix build "/workspace#nixosConfigurations.${HOST}.config.system.build.toplevel" \
    --print-out-paths --no-link)

echo "Copying store paths to ${SSH_USER}@${TARGET}..."
nix copy --to "ssh://${SSH_USER}@${TARGET}" "${SYSTEM_PATH}"

echo "Activating configuration on ${TARGET}..."
ssh ${NIX_SSHOPTS} "${SSH_USER}@${TARGET}" \
    "sudo nix-env -p /nix/var/nix/profiles/system --set ${SYSTEM_PATH} && sudo ${SYSTEM_PATH}/bin/switch-to-configuration switch"

echo "Deploy complete: ${HOST} -> ${TARGET}"
