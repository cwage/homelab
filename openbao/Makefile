SHELL := $(shell command -v bash)
DC := docker compose --env-file ../.env

.DEFAULT_GOAL := help

.PHONY: help build approle-enable approle-create-role approle-show-role approle-list shell

# Admin targets fetch the approle-admin token from KV (using the deploy
# token in .env), then run the privileged command with it. The admin token
# never touches .env or disk. EXTRA_CIDRS / EXTRA_POLICIES are passed through
# for create-role to support hosts that need extra source IPs (e.g. bao's
# 127.0.0.1/32) or extra policies on top of nixos-host (e.g. backup-remote
# attached to the containers2 role used by the containers host — though
# that one is auto-preserved on re-run, the env var is there for the
# initial attachment).
# --quiet-build: if the image doesn't exist yet, compose auto-builds it and
# the build progress would otherwise land in $$token. The whitespace check
# catches any other stray output before it gets splatted into the run args
# (an unquoted multi-word token once turned "[internal]" into a service name).
define run-admin
	@token=$$($(DC) run --rm --quiet-build --quiet-pull --entrypoint bao bao kv get -mount=kv -field=token infra/openbao/admin-token 2>/dev/null) && \
	[ -n "$$token" ] || (echo "ERROR: could not fetch admin token from kv/infra/openbao/admin-token" && exit 1) && \
	case "$$token" in *[[:space:]]*) echo "ERROR: admin token fetch returned unexpected multi-word output" && exit 1;; esac && \
	$(DC) run --rm -e BAO_TOKEN="$$token" -e EXTRA_CIDRS=$(EXTRA_CIDRS) -e EXTRA_POLICIES=$(EXTRA_POLICIES) bao $(1)
endef

help:
	@echo "OpenBao CLI operations (containerized)"
	@echo ""
	@echo "Admin targets (auto-fetch admin token from KV):"
	@echo "  make approle-enable                           Enable AppRole auth + create nixos-host policy (one-time)"
	@echo "  make approle-create-role NAME=dns1 IP=10.10.15.15 [EXTRA_CIDRS=...] [EXTRA_POLICIES=...]"
	@echo "                                                Create/upsert a role. Existing token_policies are preserved on re-run."
	@echo "  make approle-show-role NAME=dns1              Show role_id for a host"
	@echo "  make approle-list                             List all AppRole roles"
	@echo ""
	@echo "General targets (use BAO_TOKEN from .env):"
	@echo "  make build                                    Build the bao container image (jq, openssl, curl)"
	@echo "  make shell                                    Interactive bao CLI shell"
	@echo ""
	@echo "Requires BAO_ADDR and BAO_TOKEN in root .env."
	@echo "Admin targets fetch the approle-admin token from kv/infra/openbao/admin-token."

build:
	$(DC) build bao

approle-enable:
	$(call run-admin,/workspace/scripts/setup-approle.sh enable)

approle-create-role:
	@[ -n "$(NAME)" ] || (echo "ERROR: NAME required (e.g., NAME=dns1)" && exit 1)
	@[ -n "$(IP)" ] || (echo "ERROR: IP required (e.g., IP=10.10.15.15)" && exit 1)
	$(call run-admin,/workspace/scripts/setup-approle.sh create-role $(NAME) $(IP))

approle-show-role:
	@[ -n "$(NAME)" ] || (echo "ERROR: NAME required (e.g., NAME=dns1)" && exit 1)
	$(call run-admin,/workspace/scripts/setup-approle.sh show-role $(NAME))

approle-list:
	$(call run-admin,/workspace/scripts/setup-approle.sh list)

shell:
	$(DC) run --rm --entrypoint /bin/sh bao
