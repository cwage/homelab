#!/bin/bash
# Scan all container images referenced in a docker-compose file with Grype
#
# Usage: grype-compose.sh [compose-file] [grype-args...]
# Default compose file: ansible/files/stacks/docker-compose.yml

set -euo pipefail

COMPOSE_FILE="${1:-ansible/files/stacks/docker-compose.yml}"
shift || true  # Remove compose file from args, ignore if no args

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Error: Compose file not found: $COMPOSE_FILE" >&2
    exit 1
fi

# Extract image names from compose file
IMAGES=$(grep -E '^\s+image:' "$COMPOSE_FILE" | sed 's/.*image:\s*//' | tr -d '"' | tr -d "'" | sort -u)

if [[ -z "$IMAGES" ]]; then
    echo "No images found in $COMPOSE_FILE" >&2
    exit 1
fi

echo "Scanning images from: $COMPOSE_FILE"
echo "========================================"
echo ""

FAILED=0
for IMAGE in $IMAGES; do
    echo ">>> Scanning: $IMAGE"
    echo "----------------------------------------"

    if docker compose -f docker-compose.grype.yml run --rm grype "$IMAGE" "$@"; then
        echo ""
        echo "<<< $IMAGE: OK"
    else
        EXIT_CODE=$?
        echo ""
        echo "<<< $IMAGE: VULNERABILITIES FOUND (exit $EXIT_CODE)"
        FAILED=1
    fi
    echo ""
done

if [[ $FAILED -eq 1 ]]; then
    echo "========================================"
    echo "One or more images have vulnerabilities"
    exit 1
else
    echo "========================================"
    echo "All images scanned successfully"
fi
