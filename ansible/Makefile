SHELL := /bin/bash

DC := docker compose --env-file ../.env
TRUFFLEHOG_ARGS ?= filesystem /work --fail --no-update --exclude-paths /work/.trufflehog-exclude.txt

.PHONY: help init build galaxy version ping access_check proxmox proxmox-check firewall firewall-check felix felix-check nas nas-check nas-discover dns dns-check containers containers-check openbao openbao-check openbao-test gaming gaming-check gaming-configs gaming-archive backup-deploy backup-deploy-check all check-all run adhoc sh build-tinyfugue trufflehog

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t- /' | sed 's/^/make /'

init: ## Create root .env and set UID/GID for compose
	@test -f ../.env || cp ../.env.example ../.env
	sed -i "s/^UID=.*/UID=$$(id -u)/" ../.env
	sed -i "s/^GID=.*/GID=$$(id -g)/" ../.env

build: ## Build the Ansible Docker image
	$(DC) build --pull

galaxy: ## Install Ansible collections into collections/
	$(DC) run --rm ansible ansible-galaxy collection install -r requirements.yml -p collections

version: ## Show Ansible version inside container
	$(DC) run --rm ansible ansible --version

ping: ## Run the ping playbook (connectivity) [LIMIT=host]
	$(DC) run --rm ansible ansible-playbook playbooks/ping.yml -vv $(if $(LIMIT),-l $(LIMIT),) $(OPTS)

access_check: ## Verify SSH user and sudo via whoami/id
	$(DC) run --rm ansible ansible-playbook playbooks/access_check.yml -vv $(OPTS)

proxmox: ## Configure Proxmox hosts (users, mounts, etc.)
	$(DC) run --rm ansible ansible-playbook playbooks/proxmox.yml -vv $(OPTS)

proxmox-check: ## Dry-run Proxmox playbook with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/proxmox.yml -vv --check --diff $(OPTS)

firewall: ## Apply firewall configuration (pf.conf, dhcpd.conf)
	$(DC) run --rm ansible ansible-playbook playbooks/firewall.yml -vv --ask-become-pass $(OPTS)

firewall-check: ## Dry-run firewall configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/firewall.yml -vv --ask-become-pass --check --diff $(OPTS)

templates: ## Build Proxmox VM templates
	$(DC) run --rm ansible ansible-playbook playbooks/pve-templates.yml -vv $(OPTS)

felix: ## Apply felix VPS configuration (users)
	$(DC) run --rm ansible ansible-playbook playbooks/vps.yml -vv --ask-become-pass $(OPTS)

felix-check: ## Dry-run felix VPS configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/vps.yml -vv --ask-become-pass --check --diff $(OPTS)

nas: ## Apply NAS configuration (Synology NFS shares)
	$(DC) run --rm ansible ansible-playbook playbooks/nas.yml -vv --ask-become-pass $(OPTS)

nas-check: ## Dry-run NAS configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/nas.yml -vv --ask-become-pass --check --diff $(OPTS)

nas-discover: ## Run discovery mode to gather current NAS configuration
	$(DC) run --rm ansible ansible-playbook playbooks/nas.yml -vv --ask-become-pass -e discovery_mode=true --tags discovery $(OPTS)

dns: ## Configure DNS servers (NSD)
	$(DC) run --rm ansible ansible-playbook playbooks/dns.yml -vv $(OPTS)

dns-check: ## Dry-run DNS server configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/dns.yml -vv --check --diff $(OPTS)

containers: ## Configure container hosts (Docker)
	$(DC) run --rm ansible ansible-playbook playbooks/containers.yml -vv $(OPTS)

containers-check: ## Dry-run container hosts configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/containers.yml -vv --check --diff $(OPTS)

openbao: ## Configure OpenBao secrets server
	$(DC) run --rm ansible ansible-playbook playbooks/openbao.yml -vv $(OPTS)

openbao-check: ## Dry-run OpenBao configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/openbao.yml -vv --check --diff $(OPTS)

openbao-test: ## Test OpenBao connectivity and secret retrieval (requires BAO_TOKEN)
	$(DC) run --rm ansible ansible-playbook playbooks/openbao-test.yml -vv $(OPTS)

gaming: ## Full gaming server provisioning (all active profiles) [PROFILE=name]
	$(DC) run --rm ansible ansible-playbook playbooks/gaming.yml -vv $(if $(PROFILE),-e 'gaming_profile_filter=$(PROFILE)',) $(OPTS)

gaming-check: ## Dry-run gaming server config with --check/--diff [PROFILE=name]
	$(DC) run --rm ansible ansible-playbook playbooks/gaming.yml -vv --check --diff $(if $(PROFILE),-e 'gaming_profile_filter=$(PROFILE)',) $(OPTS)

gaming-configs: ## Deploy configs/mods only (skip deps/lgsm install) [PROFILE=name]
	$(DC) run --rm ansible ansible-playbook playbooks/gaming.yml -vv --tags configs $(if $(PROFILE),-e 'gaming_profile_filter=$(PROFILE)',) $(OPTS)

gaming-archive: ## Archive and purge a profile (requires PROFILE=name, CONFIRM=yes to execute)
	@if [ -z "$(PROFILE)" ]; then echo "PROFILE required. Example: make gaming-archive PROFILE=vs-buttopia"; exit 1; fi
	@archive_profile_value="$$(printf '%s' "$(PROFILE)")"; \
	archive_confirm_value="$$(printf '%s' "$(CONFIRM)")"; \
	$(DC) run --rm ansible ansible-playbook playbooks/gaming-archive.yml -vv -e archive_profile="$$archive_profile_value" $(if $(CONFIRM),-e archive_confirm="$$archive_confirm_value",) $(OPTS)

backup-deploy: ## Deploy backup tooling to containers host (builds image, writes creds)
	$(DC) run --rm ansible ansible-playbook playbooks/backup-deploy.yml -vv $(OPTS)

backup-deploy-check: ## Dry-run backup deployment with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/backup-deploy.yml -vv --check --diff $(OPTS)

all: ## Run standard playbooks (proxmox, firewall, felix)
	$(MAKE) proxmox
	$(MAKE) firewall
	$(MAKE) felix

check-all: ## Dry-run standard playbooks (proxmox, firewall, felix)
	$(MAKE) proxmox-check
	$(MAKE) firewall-check
	$(MAKE) felix-check

run: ## Run an arbitrary playbook: make run PLAY=playbooks/foo.yml [LIMIT='host'] [EXTRA_VARS='debug=true']
	@if [ -z "$(PLAY)" ]; then echo "PLAY not set. Example: make run PLAY=playbooks/users.yml"; exit 1; fi
	$(DC) run --rm ansible ansible-playbook $(PLAY) -vv $(if $(LIMIT),-l $(LIMIT),) $(if $(EXTRA_VARS),-e '$(EXTRA_VARS)',) $(OPTS)

adhoc: ## Run an ad-hoc module: make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'
	@if [ -z "$(HOSTS)" ] || [ -z "$(MODULE)" ]; then echo "HOSTS and MODULE required. Example: make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'"; exit 1; fi
	$(DC) run --rm ansible ansible all -l $(HOSTS) -m $(MODULE) $(if $(ARGS),-a '$(ARGS)',) $(OPTS)

sh: ## Interactive shell inside the Ansible container
	$(DC) run --rm ansible bash

trufflehog: ## Run a TruffleHog secrets scan (use root-level scanner)
	$(MAKE) -C .. trufflehog

build-tinyfugue: ## Build tinyfugue .deb package in Docker container
	$(DC) build tinyfugue-builder
	$(DC) run --rm tinyfugue-builder bash /files/build-tinyfugue.sh
