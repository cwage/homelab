# Backup tooling for NAS and Backblaze B2
#
# Prerequisites:
#   - BAO_TOKEN and BAO_ADDR set in root .env (for OpenBao secrets)
#   - OR: rclone credentials set in backup/.env (fallback)
#
# Secrets in OpenBao:
#   - kv/backup/backblaze: account_id, application_key
#   - kv/backup/rclone-crypt: password, password2 (salt)

DC := docker compose --env-file ../.env

.PHONY: help build shell clean

.DEFAULT_GOAL := help

help: ## Show this help
	@echo "Backup tooling"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
	@echo ""
	@echo "Example usage:"
	@echo "  make shell              # Interactive shell with rclone configured"
	@echo "  make shell CMD='rclone lsd b2:'  # List B2 buckets"
	@echo "  make shell CMD='rclone ls b2crypt:'  # List encrypted files"

build: ## Build the backup container image
	$(DC) build backup

shell: ## Open interactive shell in backup container (CMD=... for custom command)
	$(DC) run --rm backup $(CMD)

clean: ## Remove backup container image
	$(DC) down --rmi local 2>/dev/null || true
