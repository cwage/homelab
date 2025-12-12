# Lego ACME client for Let's Encrypt certificates
# Retrieves Cloudflare API token from OpenBao
#
# Prerequisites:
#   - BAO_TOKEN and BAO_ADDR set in root .env
#   - Cloudflare token stored at kv/infra/cloudflare in OpenBao

DC := docker compose --env-file ../.env

# Certificate configuration
ACME_EMAIL ?= cwage@quietlife.net
DOMAIN := lan.quietlife.net
WILDCARD := *.$(DOMAIN)

# ACME servers
ACME_PROD := https://acme-v02.api.letsencrypt.org/directory
ACME_STAGING := https://acme-staging-v02.api.letsencrypt.org/directory

# OpenBao secret paths
BAO_CF_SECRET_PATH := kv/data/infra/cloudflare
BAO_CERT_SECRET_PATH := kv/data/infra/certs/lan.quietlife.net

# Local cert files
CERT_DIR := certs/certificates
CERT_FILE := $(CERT_DIR)/_.$(DOMAIN).crt
KEY_FILE := $(CERT_DIR)/_.$(DOMAIN).key
ISSUER_FILE := $(CERT_DIR)/_.$(DOMAIN).issuer.crt

.PHONY: help run renew renew-staging renew-force list show fetch-creds store retrieve

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

# Fetch Cloudflare credentials from OpenBao
# Uses curl to call OpenBao API directly (no extra dependencies)
define fetch_cf_creds
	$(eval CF_SECRET_JSON := $(shell \
		. ../.env 2>/dev/null; \
		curl -sf \
			-H "X-Vault-Token: $${BAO_TOKEN}" \
			$${BAO_SKIP_VERIFY:+--insecure} \
			"$${BAO_ADDR}/v1/$(BAO_CF_SECRET_PATH)" \
	))
	$(eval CF_TOKEN := $(shell echo '$(CF_SECRET_JSON)' | jq -r '.data.data.api_token // empty'))
	$(eval CF_ZONE_ID := $(shell echo '$(CF_SECRET_JSON)' | jq -r '.data.data.zone_id // empty'))
	@if [ -z "$(CF_TOKEN)" ] || [ -z "$(CF_ZONE_ID)" ]; then \
		echo "ERROR: Failed to retrieve Cloudflare credentials from OpenBao"; \
		echo "Ensure BAO_TOKEN is set and kv/infra/cloudflare exists with 'api_token' and 'zone_id' fields"; \
		exit 1; \
	fi
endef

run: ## Run lego with custom arguments (ARGS="...")
	$(DC) run --rm lego $(ARGS)

renew: ## Request or renew wildcard certificate (PRODUCTION - use sparingly)
	$(call fetch_cf_creds)
	@echo "Requesting PRODUCTION certificate for $(WILDCARD) and $(DOMAIN)..."
	$(DC) run --rm -e CF_DNS_API_TOKEN="$(CF_TOKEN)" -e CF_ZONE_ID="$(CF_ZONE_ID)" lego \
		--accept-tos \
		--email=$(ACME_EMAIL) \
		--server=$(ACME_PROD) \
		--dns=cloudflare \
		--dns.resolvers=1.1.1.1:53 \
		--domains="$(WILDCARD)" \
		--domains="$(DOMAIN)" \
		run

renew-staging: ## Request certificate from STAGING (for testing, fake certs)
	$(call fetch_cf_creds)
	@echo "Requesting STAGING certificate for $(WILDCARD) and $(DOMAIN)..."
	@echo "(This will issue a fake cert - use for testing only)"
	$(DC) run --rm -e CF_DNS_API_TOKEN="$(CF_TOKEN)" -e CF_ZONE_ID="$(CF_ZONE_ID)" lego \
		--accept-tos \
		--email=$(ACME_EMAIL) \
		--server=$(ACME_STAGING) \
		--dns=cloudflare \
		--dns.resolvers=1.1.1.1:53 \
		--domains="$(WILDCARD)" \
		--domains="$(DOMAIN)" \
		run

renew-force: ## Force renewal even if certificate is still valid (PRODUCTION)
	$(call fetch_cf_creds)
	@echo "Force renewing certificate for $(WILDCARD) and $(DOMAIN)..."
	$(DC) run --rm -e CF_DNS_API_TOKEN="$(CF_TOKEN)" -e CF_ZONE_ID="$(CF_ZONE_ID)" lego \
		--accept-tos \
		--email=$(ACME_EMAIL) \
		--server=$(ACME_PROD) \
		--dns=cloudflare \
		--dns.resolvers=1.1.1.1:53 \
		--domains="$(WILDCARD)" \
		--domains="$(DOMAIN)" \
		renew --days=90

list: ## List certificates in the lego directory
	@ls -la certs/certificates/ 2>/dev/null || echo "No certificates found. Run 'make renew' first."

show: ## Show certificate details
	@if [ -f certs/certificates/_.$(DOMAIN).crt ]; then \
		openssl x509 -in certs/certificates/_.$(DOMAIN).crt -noout -subject -dates -issuer; \
	else \
		echo "No certificate found. Run 'make renew' first."; \
	fi

fetch-creds: ## Test fetching Cloudflare credentials from OpenBao (masked output)
	$(call fetch_cf_creds)
	@echo "Successfully retrieved Cloudflare credentials:"
	@echo "  API token: $(shell echo '$(CF_TOKEN)' | cut -c1-8)..."
	@echo "  Zone ID:   $(CF_ZONE_ID)"

store: ## Store local certificates in OpenBao
	@if [ ! -f $(CERT_FILE) ] || [ ! -f $(KEY_FILE) ]; then \
		echo "ERROR: Certificate files not found. Run 'make renew' or 'make renew-staging' first."; \
		exit 1; \
	fi
	@echo "Storing certificates in OpenBao at kv/infra/certs/$(DOMAIN)..."
	@. ../.env 2>/dev/null; \
	CERT=$$(cat $(CERT_FILE) | jq -sR .); \
	KEY=$$(cat $(KEY_FILE) | jq -sR .); \
	ISSUER=$$(cat $(ISSUER_FILE) | jq -sR .); \
	EXPIRES=$$(openssl x509 -in $(CERT_FILE) -noout -enddate | cut -d= -f2); \
	curl -sf \
		-X POST \
		-H "X-Vault-Token: $${BAO_TOKEN}" \
		-H "Content-Type: application/json" \
		$${BAO_SKIP_VERIFY:+--insecure} \
		-d "{\"data\": {\"certificate\": $${CERT}, \"private_key\": $${KEY}, \"issuer\": $${ISSUER}, \"expires\": \"$${EXPIRES}\", \"domain\": \"$(DOMAIN)\"}}" \
		"$${BAO_ADDR}/v1/$(BAO_CERT_SECRET_PATH)" \
	&& echo "Certificates stored successfully!" \
	|| (echo "ERROR: Failed to store certificates in OpenBao"; exit 1)

retrieve: ## Retrieve certificates from OpenBao to local files
	@echo "Retrieving certificates from OpenBao..."
	@mkdir -p $(CERT_DIR)
	@. ../.env 2>/dev/null; \
	curl -sf \
		-H "X-Vault-Token: $${BAO_TOKEN}" \
		$${BAO_SKIP_VERIFY:+--insecure} \
		"$${BAO_ADDR}/v1/$(BAO_CERT_SECRET_PATH)" > /tmp/bao_cert_response.json; \
	if [ ! -s /tmp/bao_cert_response.json ]; then \
		echo "ERROR: Failed to retrieve certificates from OpenBao"; \
		exit 1; \
	fi; \
	jq -r '.data.data.certificate' /tmp/bao_cert_response.json > $(CERT_FILE); \
	jq -r '.data.data.private_key' /tmp/bao_cert_response.json > $(KEY_FILE); \
	jq -r '.data.data.issuer' /tmp/bao_cert_response.json > $(ISSUER_FILE); \
	chmod 600 $(KEY_FILE); \
	EXPIRES=$$(jq -r '.data.data.expires' /tmp/bao_cert_response.json); \
	rm -f /tmp/bao_cert_response.json; \
	if [ -s $(CERT_FILE) ]; then \
		echo "Certificates retrieved successfully!"; \
		echo "  Expires: $$EXPIRES"; \
	else \
		echo "ERROR: Certificate file is empty - retrieval may have failed"; \
		exit 1; \
	fi
