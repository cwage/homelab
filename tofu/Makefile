.PHONY: help build shell init plan apply destroy fmt validate trufflehog clean

DC := docker compose --env-file ../.env
TRUFFLEHOG_ARGS ?= filesystem /workspace --fail --no-update --exclude-paths /workspace/.trufflehog-exclude.txt

# Default target - show help
help:
	@echo "homelab-tofu - OpenTofu infrastructure management"
	@echo ""
	@echo "Available targets:"
	@echo "  build      - Build the OpenTofu Docker image"
	@echo "  shell      - Open interactive shell in container"
	@echo "  init       - Initialize OpenTofu backend"
	@echo "  plan       - Show planned infrastructure changes"
	@echo "  apply      - Apply infrastructure changes"
	@echo "  destroy    - Destroy infrastructure (with confirmation)"
	@echo "  fmt        - Format OpenTofu files"
	@echo "  validate   - Validate OpenTofu configuration"
	@echo "  trufflehog - Run TruffleHog secrets scan"
	@echo "  clean      - Clean up Docker resources"

# Build the Docker image
build:
	$(DC) build

# Open an interactive shell in the container
shell:
	$(DC) run --rm tofu /bin/bash

# Initialize OpenTofu
init:
	$(DC) run --rm tofu tofu init

# Plan changes
plan:
	$(DC) run --rm tofu tofu plan

# Apply changes
apply:
	$(DC) run --rm tofu tofu apply

# Destroy infrastructure (interactive confirmation)
destroy:
	$(DC) run --rm tofu tofu destroy

# Format OpenTofu files
fmt:
	$(DC) run --rm tofu tofu fmt -recursive

# Validate configuration
validate:
	$(DC) run --rm tofu tofu validate

# Run TruffleHog secrets scan (root-level scanner)
trufflehog:
	$(MAKE) -C .. trufflehog

# Clean up Docker resources
clean:
	$(DC) down
	docker rmi homelab-tofu:latest 2>/dev/null || true
