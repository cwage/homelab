#!/usr/bin/env bash
# Build every deployable NixOS host's toplevel without deploying anything.
# Runs inside the Nix container via: make nix-check [HOSTS="dns1 bao"]
#
# This is the "does it still build" gate for lock bumps and module changes:
# an evaluation or build failure on any host fails the run. Nothing is
# copied anywhere. Most inputs come from cache.nixos.org, so a run is mostly
# download time.

set -euo pipefail

HOSTS="${HOSTS:-dns1 bao containers xmpp1}"
status=0

for host in ${HOSTS}; do
    echo "::group::nix build ${host}"
    if out=$(nix build "/workspace#nixosConfigurations.${host}.config.system.build.toplevel" \
            --print-out-paths --no-link); then
        echo "${host}: ${out}"
    else
        echo "${host}: BUILD FAILED"
        status=1
    fi
    echo "::endgroup::"
done

exit ${status}
