# homelab

Homelab infrastructure repo. Components:
- `ansible/` — host configuration management
- `tofu/` — VM provisioning with OpenTofu/Terraform
- `docs/` — shared design notes (e.g., `dns-plan.md`)

## Make targets
- `make ansible-<target>` runs the corresponding target in `ansible/Makefile` (see `make ansible-help` for the list).
- `make tofu-<target>` runs the corresponding target in `tofu/Makefile` (see `make tofu-help` for the list).
- `make ansible` or `make tofu` drops you into the component Makefile for ad hoc use.

Examples:
```bash
make ansible-firewall     # apply firewall config via Ansible container
make ansible-firewall-check  # dry-run firewall (check+diff)
make ansible-felix-check     # dry-run felix VPS playbook
make ansible-run PLAY=playbooks/firewall.yml LIMIT=openbsd_firewalls OPTS="--check --diff"  # dry-run limited group
make ansible-all            # run users + firewall + felix (apply)
make ansible-check-all      # dry-run users + firewall + felix
make tofu-plan            # show OpenTofu plan
make tofu-shell           # interactive tofu container
make ansible-trufflehog   # run secrets scan for Ansible tree
make tofu-trufflehog      # run secrets scan for Tofu tree
make trufflehog           # scan entire repo for secrets (root-level)
make install-precommit-hook  # install root pre-commit hook (trufflehog)
```

### Common scenarios
- **Firewall only (apply)**: `make ansible-firewall`
- **Firewall dry-run**: `make ansible-firewall-check` (or add `OPTS="--check --diff"` to other targets)
- **Felix VPS dry-run**: `make ansible-felix-check`
- **Limit to a group/host**: `make ansible-run PLAY=playbooks/firewall.yml LIMIT=openbsd_firewalls` (add `OPTS="--check --diff"` for dry-run)
- **Apply to all standard playbooks**: `make ansible-all` (users, firewall, felix) — use sparingly
- **Dry-run all standard playbooks**: `make ansible-check-all`

### Secrets and local state
- OpenTofu API creds live in `tofu/.env` (gitignored). Copy from your old checkout if needed.
- Ansible deploy keys live in `ansible/keys/` (gitignored).
- Other local artifacts (.tfstate, .terraform, etc.) remain gitignored via component `.gitignore` files.

### TruffleHog scanning
- Root scanner: `make trufflehog` (uses `docker-compose.trufflehog.yml` in repo root, excludes defined in `.trufflehog-exclude.txt`).
- Install pre-commit hook: `make install-precommit-hook` (respects `SKIP_TRUFFLEHOG=1` and `TRUFFLEHOG_PRECOMMIT_ARGS`).
