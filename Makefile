SHELL := $(shell command -v bash)

ANSIBLE_DIR := ansible
TOFU_DIR := tofu
LEGO_DIR := lego
BACKUP_DIR := backup
NIX_DIR := nix
OPENBAO_DIR := openbao

ANSIBLE_TARGETS := help init build galaxy version ping access_check proxmox proxmox-check firewall firewall-check openbao-test felix felix-check gaming gaming-check gaming-configs gaming-archive all check-all run adhoc sh build-tinyfugue trufflehog refresh-known-hosts
TOFU_TARGETS := help build shell init plan apply destroy fmt validate trufflehog clean
LEGO_TARGETS := help run renew renew-staging renew-force list show fetch-creds store retrieve
BACKUP_TARGETS := help build shell clean local local-dry b2 b2-dry
NIX_TARGETS := help build shell template deploy deploy-host clean clean-all
OPENBAO_TARGETS := help build approle-enable approle-create-role approle-show-role approle-list shell
TRUFFLEHOG_ARGS ?= filesystem /repo --fail --no-update --exclude-paths /repo/.trufflehog-exclude.txt

.DEFAULT_GOAL := help

.PHONY: help ansible tofu lego backup nix openbao ansible-% tofu-% lego-% backup-% nix-% openbao-% trufflehog install-precommit-hook bao-preflight bao-token-status

help:
	@echo "homelab monorepo"
	@echo ""
	@echo "Use namespaced targets to drive component Makefiles:"
	@echo "  make ansible-<target>   (common: $(ANSIBLE_TARGETS))"
	@echo "                          Run 'make ansible-help' for the full list."
	@echo "  make tofu-<target>      (targets: $(TOFU_TARGETS))"
	@echo "  make lego-<target>      (targets: $(LEGO_TARGETS))"
	@echo "  make backup-<target>    (targets: $(BACKUP_TARGETS))"
	@echo "  make nix-<target>       (targets: $(NIX_TARGETS))"
	@echo "  make openbao-<target>   (targets: $(OPENBAO_TARGETS))"
	@echo "  make trufflehog         (root) scan entire repo for secrets"
	@echo "  make bao-token-status   (root) show workstation OpenBao token TTL/expiry"
	@echo ""
	@echo "ansible-*/tofu-* targets preflight the OpenBao token first (fail fast"
	@echo "instead of a cryptic 403 mid-run). Bypass with SKIP_BAO_PREFLIGHT=1."
	@echo ""
	@echo "Shortcuts:"
	@echo "  make ansible            # same as: (cd ansible && make)  -> opens component help/defaults"
	@echo "  make tofu               # same as: (cd tofu && make)     -> opens component help/defaults"
	@echo "  make lego               # same as: (cd lego && make)     -> opens component help/defaults"
	@echo "  make backup             # same as: (cd backup && make)   -> opens component help/defaults"
	@echo "  make nix                # same as: (cd nix && make)      -> opens component help/defaults"
	@echo "  make openbao            # same as: (cd openbao && make)  -> opens component help/defaults"
	@echo "  make install-precommit-hook # install root pre-commit hook (trufflehog)"

# Fail fast if the workstation OpenBao token is missing, expired, or expiring
# within a day — the alternative is a cryptic 403 deep inside a playbook or
# tofu provider (#242). SKIP_BAO_PREFLIGHT=1 bypasses the check (e.g. for
# targets that don't touch OpenBao, or when bao itself is down).
bao-preflight:
# Only explicit truthy values disable the guard — SKIP_BAO_PREFLIGHT=0,
# empty, or unset all keep the check active.
ifeq ($(filter 1 true yes,$(SKIP_BAO_PREFLIGHT)),)
	@./bin/bao-token-status --check-min-ttl=1d || { echo "ERROR: OpenBao preflight failed — renew BAO_TOKEN and update .env (docs/openbao-secrets.md), or bypass with SKIP_BAO_PREFLIGHT=1"; exit 1; }
endif

bao-token-status:
	@./bin/bao-token-status

ansible-%: bao-preflight
	@$(MAKE) -C $(ANSIBLE_DIR) $*

tofu-%: bao-preflight
	@$(MAKE) -C $(TOFU_DIR) $*

ansible:
	@$(MAKE) -C $(ANSIBLE_DIR)

tofu:
	@$(MAKE) -C $(TOFU_DIR)

lego-%:
	@$(MAKE) -C $(LEGO_DIR) $*

lego:
	@$(MAKE) -C $(LEGO_DIR)

backup-%:
	@$(MAKE) -C $(BACKUP_DIR) $*

backup:
	@$(MAKE) -C $(BACKUP_DIR)

nix-%:
	@$(MAKE) -C $(NIX_DIR) $*

nix:
	@$(MAKE) -C $(NIX_DIR)

openbao-%:
	@$(MAKE) -C $(OPENBAO_DIR) $*

openbao:
	@$(MAKE) -C $(OPENBAO_DIR)

trufflehog:
	docker compose -f docker-compose.trufflehog.yml run --rm trufflehog $(TRUFFLEHOG_ARGS)

install-precommit-hook:
	@./scripts/install-precommit-hook.sh
