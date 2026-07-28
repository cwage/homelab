.PHONY: help build shell init plan apply run destroy fmt validate trufflehog clean

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
	@echo "  plan       - Show planned infrastructure changes [OPTS=...]"
	@echo "  apply      - Apply infrastructure changes [OPTS=...]"
	@echo "  run        - Run an arbitrary tofu command: make tofu-run ARGS='import <addr> <id>'"
	@echo "  destroy    - Destroy ALL infrastructure — you almost never want this"
	@echo ""
	@echo "  OPTS passes flags through to tofu:"
	@echo "    -target=<resource>   scope plan/apply to one resource (leaves it in place)"
	@echo "    -replace=<resource>  DESTROY and recreate that one resource"
	@echo "  e.g. make tofu-apply OPTS='-target=linode_firewall.xmpp1'"
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
# OPTS passes through to tofu. -target scopes to one resource; -replace
# forces destroy+recreate of one resource (read the plan before applying):
#   make tofu-plan OPTS='-target=linode_firewall.xmpp1'
plan:
	$(DC) run --rm tofu tofu plan $(OPTS)

# Apply changes
# Use OPTS for targeted operations rather than reaching for `destroy`, which
# tears down the ENTIRE fleet. Note the difference:
#   make tofu-apply OPTS='-target=linode_firewall.xmpp1'    # scope only
#   make tofu-apply OPTS='-replace=linode_instance.xmpp1'   # destroy+recreate
apply:
	$(DC) run --rm tofu tofu apply $(OPTS)

# Run an arbitrary tofu command, e.g. adopting an existing resource:
#   make tofu-run ARGS='import linode_instance.felix 12345'
run:
	$(DC) run --rm tofu tofu $(ARGS)

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
