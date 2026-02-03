SHELL := /bin/bash

ANSIBLE_DIR := ansible
TOFU_DIR := tofu
LEGO_DIR := lego

ANSIBLE_TARGETS := help init build galaxy version ping access_check proxmox proxmox-check firewall firewall-check felix felix-check all check-all run adhoc sh build-tinyfugue trufflehog
TOFU_TARGETS := help build shell init plan apply destroy fmt validate trufflehog clean
LEGO_TARGETS := help run renew renew-staging renew-force list show fetch-creds store retrieve
TRUFFLEHOG_ARGS ?= filesystem /repo --fail --no-update --exclude-paths /repo/.trufflehog-exclude.txt

.DEFAULT_GOAL := help

.PHONY: help ansible tofu lego ansible-% tofu-% lego-% trufflehog grype grype-compose grype-pull install-precommit-hook

help:
	@echo "homelab monorepo"
	@echo ""
	@echo "Use namespaced targets to drive component Makefiles:"
	@echo "  make ansible-<target>   (targets: $(ANSIBLE_TARGETS))"
	@echo "  make tofu-<target>      (targets: $(TOFU_TARGETS))"
	@echo "  make lego-<target>      (targets: $(LEGO_TARGETS))"
	@echo "  make trufflehog         (root) scan entire repo for secrets"
	@echo "  make grype IMAGE=<img>  (root) scan a container image for CVEs"
	@echo "  make grype-compose      (root) scan all images in production compose"
	@echo "  make grype-pull         (root) pull the grype scanner image"
	@echo ""
	@echo "Shortcuts:"
	@echo "  make ansible            # same as: (cd ansible && make)  -> opens component help/defaults"
	@echo "  make tofu               # same as: (cd tofu && make)     -> opens component help/defaults"
	@echo "  make lego               # same as: (cd lego && make)     -> opens component help/defaults"
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

trufflehog:
	docker compose -f docker-compose.trufflehog.yml run --rm trufflehog $(TRUFFLEHOG_ARGS)

# Grype vulnerability scanning
GRYPE_ARGS ?=
IMAGE ?=

grype-pull:
	docker compose -f docker-compose.grype.yml pull

grype:
ifndef IMAGE
	$(error IMAGE is required. Usage: make grype IMAGE=nginx:latest)
endif
	docker compose -f docker-compose.grype.yml run --rm grype $(IMAGE) $(GRYPE_ARGS)

grype-compose:
	./scripts/grype-compose.sh ansible/files/stacks/docker-compose.yml $(GRYPE_ARGS)

install-precommit-hook:
	@./scripts/install-precommit-hook.sh
