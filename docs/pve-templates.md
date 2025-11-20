# Proxmox template workflow

How to add and build new VM templates using the OpenTofu-managed base images and the Ansible role in this repo.

## 1) Add/verify the base image in OpenTofu

- Define the upstream image in `tofu/images.tf` (see the existing Debian 12 example). Set:
  - `file_name`: the on-disk name Proxmox expects (e.g., `debian-12-genericcloud-amd64.img`).
  - `url`: upstream image URL (often qcow2 for cloud images).
  - `content_type`/`datastore_id` in the `proxmox_virtual_environment_download_file` resource.
- Run `make tofu-plan` and `make tofu-apply` to download the image onto the Proxmox datastore (defaults are in `tofu/variables.tf`). The downloaded path should match `pve_template_image_dir` (defaults to `/var/lib/vz/template/iso`).

## 2) Describe the template for Ansible

- In `ansible/inventories/group_vars/proxmox.yml`, add an entry to `pve_templates`:
  - `name`: template/VM name (hostname-safe).
  - `vmid`: >= `pve_template_min_vmid` (default 9000); unique per template.
  - `image_file`: must match the `file_name` from OpenTofu.
  - `datastore`, `bridge`, memory/cores, and `ciuser` (default is `deploy`).
  - Optional: `fqdn`, `description`, `packages`, `snippet_storage`.
- Ensure the deploy pubkey file referenced by `pve_template_deploy_pubkey_path` exists (default `ansible/keys/deploy.pub`).

## 3) Build the template

- From repo root: `make ansible-templates` (runs `ansible/playbooks/pve-templates.yml`).
- The role will:
  - Validate VMID floor and ensure the image exists.
  - Render cloud-init user-data with the deploy user + pubkey and qemu-guest-agent enabled.
  - Create/replace the VM (only destroys an existing VMID if it is already a template, unless `pve_template_force_recreate=true`).
  - Boot, wait for cloud-init + qemu-guest-agent, then shut down and convert to a template.

## 4) Using the template

- Downstream VM definitions (OpenTofu or manual) can now clone from the template ID/VMID.
- Cloud-init will include the deploy user/key; additional users/keys should come from your per-VM IaC (e.g., OpenTofu cloud-init config or Ansible roles).

## Notes

- The Proxmox API does not expose all template import steps, so disk import + template creation currently happens via Ansible `qm` commands on the node.
- If you need to replace a non-template VM that reuses a VMID, set `pve_template_force_recreate=true` in inventory to allow the role to purge it.
