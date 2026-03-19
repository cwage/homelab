#!/usr/bin/env bash
set -euo pipefail

cd /workspace

echo "Building NixOS Proxmox template image..."

# --out-link in /tmp avoids creating a root-owned 'result' symlink on the
# bind-mounted repo checkout
nix build .#proxmox-template --out-link /tmp/result --print-build-logs

# Fix ownership of flake.lock if nix created/updated it (first build)
if [ -n "${OUTPUT_UID:-}" ] && [ -n "${OUTPUT_GID:-}" ]; then
    if [ -f flake.lock ]; then
        chown "${OUTPUT_UID}:${OUTPUT_GID}" flake.lock
    fi
fi

VMA_FILE=$(find -L /tmp/result -name '*.vma.zst' -print -quit 2>/dev/null || true)

if [ -z "$VMA_FILE" ]; then
    echo "ERROR: No .vma.zst file found in build output"
    echo "Build result contents:"
    ls -la /tmp/result/
    exit 1
fi

mkdir -p /output
cp "$VMA_FILE" /output/
OUTPUT_FILE="/output/$(basename "$VMA_FILE")"

if [ -n "${OUTPUT_UID:-}" ] && [ -n "${OUTPUT_GID:-}" ]; then
    chown "${OUTPUT_UID}:${OUTPUT_GID}" "$OUTPUT_FILE"
fi

echo ""
echo "Build complete:"
ls -lh "$OUTPUT_FILE"
echo ""
echo "To deploy to Proxmox:"
echo "  1. scp $OUTPUT_FILE pve1:/var/lib/vz/dump/"
echo "  2. ssh pve1 qmrestore /var/lib/vz/dump/$(basename "$VMA_FILE") 9001 --unique true"
echo "  3. ssh pve1 qm template 9001"
