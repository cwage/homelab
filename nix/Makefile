.PHONY: help build shell template deploy clean

DC := docker compose --env-file ../.env
VMA_FILE := vzdump-qemu-nixos-template.vma.zst
TEMPLATE_VMID := 9001
PVE_HOST := pve1
PVE_DUMP_DIR := /var/lib/vz/dump
SSH_KEY := ../ansible/keys/deploy
SSH_USER := deploy
SSH_OPTS := -i $(SSH_KEY) -o StrictHostKeyChecking=accept-new

help:
	@echo "homelab-nix - NixOS image builder"
	@echo ""
	@echo "Available targets:"
	@echo "  build     - Build the Nix builder Docker image"
	@echo "  shell     - Open interactive shell in Nix container"
	@echo "  template  - Build the NixOS Proxmox VMA template image"
	@echo "  deploy    - Upload VMA to Proxmox, restore as VM, convert to template"
	@echo "  clean     - Remove Docker resources and build output"

build:
	$(DC) build

shell:
	$(DC) run --rm --entrypoint bash nix

template:
	@mkdir -p output
	$(DC) run --rm --entrypoint bash nix /workspace/nix/build.sh

deploy: output/$(VMA_FILE)
	scp $(SSH_OPTS) output/$(VMA_FILE) $(SSH_USER)@$(PVE_HOST):/tmp/$(VMA_FILE)
	ssh $(SSH_OPTS) $(SSH_USER)@$(PVE_HOST) sudo mv /tmp/$(VMA_FILE) $(PVE_DUMP_DIR)/
	ssh $(SSH_OPTS) $(SSH_USER)@$(PVE_HOST) sudo qmrestore $(PVE_DUMP_DIR)/$(VMA_FILE) $(TEMPLATE_VMID) --unique true
	ssh $(SSH_OPTS) $(SSH_USER)@$(PVE_HOST) sudo qm template $(TEMPLATE_VMID)
	@echo ""
	@echo "Template $(TEMPLATE_VMID) created on $(PVE_HOST)"

output/$(VMA_FILE):
	@echo "No VMA image found. Run 'make template' first."
	@exit 1

clean:
	$(DC) down
	docker rmi homelab-nix:latest 2>/dev/null || true
	rm -rf output/
