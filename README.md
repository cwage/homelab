# homelab

Homelab infrastructure repo. Components:
- `ansible/` — host configuration management
- `tofu/` — VM provisioning with OpenTofu/Terraform
- `testing/` — testing/preview containers (e.g., resume preview via Jekyll)
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
make ansible-gaming          # provision gaming servers (all active profiles)
make ansible-gaming-check    # dry-run gaming server config
make ansible-gaming PROFILE=vs-buttopia  # provision specific profile only
make ansible-gaming-configs  # deploy configs/mods only (no deps/lgsm install)
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

### Gaming servers
Game servers on Linode VPS. Each game profile gets its own Linux user with isolated installation.

#### Quick reference
| Command | Description |
|---------|-------------|
| `make ansible-gaming` | Full provision (all active profiles) |
| `make ansible-gaming PROFILE=name` | Full provision (single profile) |
| `make ansible-gaming-check` | Dry-run with --check/--diff |
| `make ansible-gaming-configs` | Deploy configs/mods only |
| `make ansible-gaming-archive PROFILE=name` | Archive and purge a profile |

#### New profile setup

1. Add profile to `ansible/inventories/group_vars/gaming_servers.yml`
2. Run `make ansible-gaming PROFILE=<name>` to provision user and dependencies
3. Install the game server (see game-specific instructions below)
4. Start the server and verify it works
5. (Optional) Add configs/mods to `ansible/roles/gaming_server/files/profiles/<name>/`
6. Deploy configs with `make ansible-gaming-configs PROFILE=<name>`

#### Game-specific setup

**Vintage Story / Valheim (LinuxGSM)**

After provisioning, install the game via LGSM:
```bash
ssh gaming.quietlife.net
sudo -iu <profile>
./<script> install    # e.g., ./vintsserver install, ./vhserver install
./<script> start
```

#### Day-to-day operations

Ansible never auto-restarts game servers. After config changes, manually restart:
```bash
ssh gaming.quietlife.net
sudo -iu <profile>
./<script> restart
```

#### Archiving profiles

To safely remove a profile and reclaim disk space:

1. Set `active: false` in `ansible/inventories/group_vars/gaming_servers.yml`
2. Stop the server: `sudo -iu <profile> ./<script> stop`
3. Preview: `make ansible-gaming-archive PROFILE=<name>`
4. Execute: `make ansible-gaming-archive PROFILE=<name> CONFIRM=yes`
5. Copy the tarball: `scp gaming.quietlife.net:/tmp/<name>-*.tar.gz ./`

To restore later:
1. Set `active: true` in group_vars
2. Run `make ansible-gaming PROFILE=<name>`
3. Extract the tarball to restore world data

### Resume preview (testing container)

Preview a resume branch at `preview.quietlife.net` before merging to master/GitHub Pages.

| Command | Description |
|---------|-------------|
| `make ansible-testing-deploy` | Full deploy (copy files, build, start container) |
| `make ansible-testing-deploy-check` | Dry-run deploy |
| `make ansible-testing-refresh` | Restart container (pulls latest from current branch) |
| `make ansible-testing-switch BRANCH=master` | Switch to a different branch and restart |
| `make testing-build` | Build the Docker image locally |

Day-to-day workflow: edit resume locally, `git push`, then `make ansible-testing-refresh` to see changes at `preview.quietlife.net`.

### Secrets and local state
- OpenTofu API creds live in `tofu/.env` (gitignored).
- Ansible deploy keys live in `ansible/keys/` (gitignored).
- Other local artifacts (.tfstate, .terraform, etc.) remain gitignored via component `.gitignore` files.

### TruffleHog scanning
- Root scanner: `make trufflehog` (uses `docker-compose.trufflehog.yml` in repo root, excludes defined in `.trufflehog-exclude.txt`).
- Install pre-commit hook: `make install-precommit-hook` (respects `SKIP_TRUFFLEHOG=1` and `TRUFFLEHOG_PRECOMMIT_ARGS`).
