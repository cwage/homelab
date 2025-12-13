# Homelab monorepo agent guide

## BEFORE MAKING ANY CODE CHANGES
- [ ] Check current branch with `git branch --show-current`
- [ ] If on `master`, STOP and alert the user to create/switch to a feature branch first
- [ ] Only proceed with code changes once on a non-master branch

---

- **Layout**: `ansible/` (host config, formerly homelab-ansible), `tofu/` (OpenTofu VM provisioning, formerly homelab-tofu), `docs/` (design notes like `docs/dns-plan.md`).
- **Make wrappers**: From repo root use `make ansible-<target>` and `make tofu-<target>` to call component Makefiles (see `make ansible-help`, `make tofu-help`). Avoid running `ansible-playbook` or `tofu` directly; prefer the Dockerized targets.
- **Containerized workflows**: Both stacks expect Docker/Compose; use provided Make targets for build/plan/apply/lint. Keep secrets in local `.env` files (gitignored) and never commit keys or state.
- **DNS direction**: We standardized on NSD as the authoritative server (`lan.quietlife.net`), with Unbound on the firewall as recursive + stub to NSD. DHCP/DNS should be driven from a shared data model; include an `dhcp-<nn>.lan.quietlife.net` pool for ephemeral clients. See `docs/dns-plan.md`.
- **Host data**: Inventories and templates live under `ansible/` (e.g., `inventories/hosts.yml`, `roles/openbsd_firewall`). Keep DHCP reservations, DNS records, and VM definitions consistent by editing shared host metadata when adding nodes.
- **Networking**: Proxmox hosts only expose a single useful bridge (`vmbr0`). Assume VMs (even ones with multiple NICs) attach to that same bridge unless the user explicitly requests a different network.
- **Testing/validation**: Run relevant Dockerized checks before changes: `make ansible-trufflehog`, `make tofu-validate/plan`, `make ansible-ping`/`ansible-firewall` dry runs as needed. Keep changes scoped; avoid large “deploy everything” unless required.
- **No destructive ops**: Don't use sudo; avoid wiping state or force pushes. If you must propose a destructive command, surface it to the user instead of running it.
- **No service restarts without approval**: NEVER restart containers, services, or VMs without explicit user approval. Always ask first - even if a restart seems like the obvious fix. Diagnose the problem, explain the fix, and let the user decide when to restart.
- **Deployment workflow**: Do NOT automatically deploy changes (ansible playbooks, tofu apply, etc.) without explicit user approval. After making code changes, ask the user if they want to deploy rather than assuming. The user prefers to review and deploy manually so they can observe and learn. Only run `make ansible-*` or `make tofu-apply` when the user explicitly requests it or approves it.
- **Git workflow**: The user will handle git commits and PR creation. Do NOT run `git commit`, `git push`, or `gh pr create` unless explicitly asked. Focus on making code changes; the user will review and commit them. **Important**: Before making code changes, verify you're not on `master` branch. If on master, alert the user so they can create/switch to an appropriate feature branch first.
- **SSH key errors**: If you encounter SSH permission denied errors (e.g., `git@github.com: Permission denied (publickey)`), simply ask the user to add their SSH key (it's passphrase-protected) and then retry the command. Don't attempt to run ssh-agent or ssh-add yourself.
- **IP address allocation**: Before assigning a static IP to a new VM, always verify it's not already in use by checking `ansible/roles/openbsd_firewall/templates/dhcpd.conf.j2` for existing reservations and running `ping -c1 <ip>` to confirm no active host. Prefer IPs in the 10.10.15.10-99 range for infrastructure VMs (the .100-.254 range is the DHCP pool).
- **NEVER read or display secrets**: Do NOT run commands that would output tokens, passwords, API keys, or other secrets. If troubleshooting involves secrets (OpenBao tokens, GPG passphrases, bridge credentials, etc.), ask the user to run the diagnostic commands themselves. Never run `cat`, `sudo cat`, or any command on files containing secrets (e.g., `.bao_token`, `.env`, credentials files). Never include secret values in chat output.
