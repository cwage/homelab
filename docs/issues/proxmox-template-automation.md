# Issue: Proxmox VM image import requires SSH; need API-only path

## Problem
- The `bpg/proxmox` provider uses the Proxmox API for most VM actions, but shells over SSH to run `qm importdisk`/`qemu-img` when attaching a raw/qcow2 image to a VM datastore.
- Current Tofu flow mounts the downloaded Debian cloud image (`debian-12-genericcloud-amd64.img`) as `scsi0` on a new VM. At apply time, the provider attempts the SSH hop and fails if no SSH auth is available inside the Docker container.
- We don’t want SSH in the apply path; API-token-only IaC is the goal.

## Options
1) **Accept provider SSH for imports** (status quo): forward ssh-agent into the container and set `ssh.username` so `qm importdisk` works. Undesirable as a steady state.
2) **Pre-stage cloud-init templates on the node** (preferred): Manually or via Ansible, create a template VM per base image (e.g., Debian 12) by running `qm create`, `qm importdisk`, `qm template`. Then Tofu resources can `clone` from the template, which is API-only.
3) **Custom upload path**: If Proxmox ever exposes an API for disk import, switch to it. Today there isn’t one, so the provider’s SSH workaround is required for fresh imports.

## Proposed resolution
- Add an Ansible role/task that runs on the Proxmox host (with `become: true`) to:
  - Ensure the cloud image is present (already downloaded by Tofu to `template/iso`).
  - Create/refresh a template VM (VMID, name, bridge, scsihw, cloud-init drive).
  - `qm importdisk` the image into the VM datastore, attach `scsi0`, set boot order, enable agent, and mark as template.
- Update Tofu VM resources to clone from the template VMID instead of importing the image directly. This removes SSH from apply.

## Next steps
- Pick a canonical template VMID (e.g., 9000) and datastore/bridge defaults.
- Add the Ansible task to the Proxmox host play, parameterized by image path/datastore/bridge.
- Update Tofu VM definitions to use `clone { vm_id = <template_id>; full = true; datastore_id = var.pm_vm_datastore_id }`.
- Document how to refresh templates when base images are updated.
