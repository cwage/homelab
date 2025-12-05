.PHONY: help build shell init plan apply destroy fmt validate trufflehog clean

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
	docker compose build

# Open an interactive shell in the container
shell:
	docker compose run --rm tofu /bin/bash

# Initialize OpenTofu
init:
	docker compose run --rm tofu tofu init

# Check if state files are up-to-date with origin/master
check-state:
	@git fetch origin master --quiet && \
	LOCAL_STATE=$$(git show HEAD:tofu/terraform.tfstate 2>/dev/null | md5sum) && \
	REMOTE_STATE=$$(git show origin/master:tofu/terraform.tfstate 2>/dev/null | md5sum) && \
	if [ "$$LOCAL_STATE" != "$$REMOTE_STATE" ]; then \
		echo "ERROR: terraform.tfstate differs from origin/master. Pull/rebase state changes before running tofu."; \
		exit 1; \
	fi

# Plan changes
plan: check-state
	docker compose run --rm tofu tofu plan

# Apply changes
apply: check-state
	docker compose run --rm tofu tofu apply

# Destroy infrastructure (interactive confirmation)
destroy:
	docker compose run --rm tofu tofu destroy

# Format OpenTofu files
fmt:
	docker compose run --rm tofu tofu fmt -recursive

# Validate configuration
validate:
	docker compose run --rm tofu tofu validate

# Run TruffleHog secrets scan (root-level scanner)
trufflehog:
	$(MAKE) -C .. trufflehog

# Clean up Docker resources
clean:
	docker compose down
	docker rmi homelab-tofu:latest 2>/dev/null || true
