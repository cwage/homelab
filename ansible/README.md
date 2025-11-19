# Homelab Ansible

Minimal Ansible setup to manage a Proxmox host.

## Setup

- Requires Ansible installed locally (ansible-core or ansible).
- Inventory defines a `proxmox` group with host alias `pve1` at `10.10.15.18`.

### SSH key placement

- Put the private key for the `deploy` user at: `keys/deploy/id_ed25519`
  - Ensure permissions are `0600` on the file.
  - The corresponding public key must be in `/home/deploy/.ssh/authorized_keys` on the Proxmox node.
- `ansible.cfg` is preconfigured to use:
  - `remote_user = deploy`
  - `private_key_file = keys/deploy/id_ed25519`
  - `inventory = inventories/hosts.yml`

### Proxmox host

- Inventory file: `inventories/hosts.yml`
  - Group: `proxmox`
  - Host alias: `pve1` -> `10.10.15.18`

### Test connectivity

Once the `deploy` user exists on the Proxmox host with passwordless sudo and the SSH key is installed, test with either command:

```
ansible -i inventories/hosts.yml proxmox -m ping
```

or

```
ansible-playbook playbooks/ping.yml
```

Notes:
- Host key checking is disabled in `ansible.cfg` for convenience during bootstrap. Consider enabling it later.
- Privilege escalation (`become: true` with `sudo`) is enabled by default.

## Run via Docker/Compose (no local Ansible)

1) Copy `.env.example` to `.env` and set your UID/GID (Linux/macOS):

```
cp .env.example .env
id -u | xargs -I{} sed -i "s/^UID=.*/UID={}/" .env
id -g | xargs -I{} sed -i "s/^GID=.*/GID={}/" .env
```

2) Build the Ansible image:

```
docker compose build --pull
```

3) Verify Ansible inside the container:

```
docker compose run --rm ansible ansible --version
```

4) Test connectivity to Proxmox:

```
docker compose run --rm ansible ansible-playbook playbooks/ping.yml -vv
```

The container mounts this repo at `/work`, uses `/work/ansible.cfg`, and reads the key at `keys/deploy`.

SELinux note
- The compose volume uses `./:/work:Z`. The `:Z` option relabels the bind mount with a private SELinux label so the container can access it on SELinux systems (Fedora/RHEL). It is ignored on non‑SELinux hosts.

## Secret scanning and pre-commit hook

TruffleHog runs inside Docker (service `trufflehog` defined in `docker-compose.yml`) to keep scans reproducible and avoid installing it locally.

### One-off scans

```
make trufflehog
```

The target wraps `docker compose run --rm trufflehog filesystem /work --fail --no-update` with a repo-specific exclude file to skip vendored collections and secrets you already manage out-of-band (e.g., `keys/deploy`). Override the command via `TRUFFLEHOG_ARGS` if you need additional flags:

```
make trufflehog TRUFFLEHOG_ARGS="filesystem /work --fail --only-verified"
```

### Installing the git pre-commit hook

To catch leaks before the CI pipeline, install the repo-managed hook into `.git/hooks/pre-commit`:

```
./scripts/install-precommit-hook.sh
```

After installation, every `git commit` runs the same Dockerized scan. Set `SKIP_TRUFFLEHOG=1` to bypass temporarily or `TRUFFLEHOG_PRECOMMIT_ARGS="..."` to customize the hook invocation (use sparingly and document why).

Make sure CI mirrors `make trufflehog` (recommended) so pushes and PRs are blocked if the scan fails, even when someone skips the local hook.
