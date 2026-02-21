SHELL := /bin/bash

ANSIBLE_DIR := ansible
TOFU_DIR := tofu
LEGO_DIR := lego
BACKUP_DIR := backup

ANSIBLE_TARGETS := help init build galaxy version ping access_check proxmox proxmox-check firewall firewall-check felix felix-check backup-deploy backup-deploy-check all check-all run adhoc sh build-tinyfugue trufflehog
TOFU_TARGETS := help build shell init plan apply destroy fmt validate trufflehog clean
LEGO_TARGETS := help run renew renew-staging renew-force list show fetch-creds store retrieve
BACKUP_TARGETS := help build shell clean
TRUFFLEHOG_ARGS ?= filesystem /repo --fail --no-update --exclude-paths /repo/.trufflehog-exclude.txt

.DEFAULT_GOAL := help

.PHONY: help ansible tofu lego backup ansible-% tofu-% lego-% backup-% trufflehog install-precommit-hook

help:
	@echo "homelab monorepo"
	@echo ""
	@echo "Use namespaced targets to drive component Makefiles:"
	@echo "  make ansible-<target>   (targets: $(ANSIBLE_TARGETS))"
	@echo "  make tofu-<target>      (targets: $(TOFU_TARGETS))"
	@echo "  make lego-<target>      (targets: $(LEGO_TARGETS))"
	@echo "  make backup-<target>    (targets: $(BACKUP_TARGETS))"
	@echo "  make trufflehog         (root) scan entire repo for secrets"
	@echo ""
	@echo "Shortcuts:"
	@echo "  make ansible            # same as: (cd ansible && make)  -> opens component help/defaults"
	@echo "  make tofu               # same as: (cd tofu && make)     -> opens component help/defaults"
	@echo "  make lego               # same as: (cd lego && make)     -> opens component help/defaults"
	@echo "  make backup             # same as: (cd backup && make)   -> opens component help/defaults"
	@echo "  make install-precommit-hook # install root pre-commit hook (trufflehog)"

ansible-%:
	@$(MAKE) -C $(ANSIBLE_DIR) $*

tofu-%:
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

trufflehog:
	docker compose -f docker-compose.trufflehog.yml run --rm trufflehog $(TRUFFLEHOG_ARGS)

install-precommit-hook:
	@./scripts/install-precommit-hook.sh
