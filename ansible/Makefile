SHELL := /bin/bash

DC := docker compose
TRUFFLEHOG_ARGS ?= filesystem /work --fail --no-update --exclude-paths /work/.trufflehog-exclude.txt

.PHONY: help init build galaxy version ping access_check users users-check firewall firewall-check felix felix-check all check-all run adhoc sh build-tinyfugue trufflehog

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sed 's/:.*## /\t- /' | sed 's/^/make /'

init: ## Create .env and set UID/GID for compose
	@test -f .env || cp .env.example .env
	sed -i "s/^UID=.*/UID=$$(id -u)/" .env
	sed -i "s/^GID=.*/GID=$$(id -g)/" .env

build: ## Build the Ansible Docker image
	$(DC) build --pull

galaxy: ## Install Ansible collections into collections/
	$(DC) run --rm ansible ansible-galaxy collection install -r requirements.yml -p collections

version: ## Show Ansible version inside container
	$(DC) run --rm ansible ansible --version

ping: ## Run the ping playbook (connectivity)
	$(DC) run --rm ansible ansible-playbook playbooks/ping.yml -vv $(OPTS)

access_check: ## Verify SSH user and sudo via whoami/id
	$(DC) run --rm ansible ansible-playbook playbooks/access_check.yml -vv $(OPTS)

users: ## Apply users role (deploy and others)
	$(DC) run --rm ansible ansible-playbook playbooks/users.yml -vv $(OPTS)

users-check: ## Dry-run users playbook with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/users.yml -vv --check --diff $(OPTS)

firewall: ## Apply firewall configuration (pf.conf, dhcpd.conf)
	$(DC) run --rm ansible ansible-playbook playbooks/firewall.yml -vv --ask-become-pass $(OPTS)

firewall-check: ## Dry-run firewall configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/firewall.yml -vv --ask-become-pass --check --diff $(OPTS)

felix: ## Apply felix VPS configuration (users)
	$(DC) run --rm ansible ansible-playbook playbooks/vps.yml -vv --ask-become-pass $(OPTS)

felix-check: ## Dry-run felix VPS configuration with --check/--diff
	$(DC) run --rm ansible ansible-playbook playbooks/vps.yml -vv --ask-become-pass --check --diff $(OPTS)

all: ## Run standard playbooks (users, firewall, felix)
	$(MAKE) users
	$(MAKE) firewall
	$(MAKE) felix

check-all: ## Dry-run standard playbooks (users, firewall, felix)
	$(MAKE) users-check
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
