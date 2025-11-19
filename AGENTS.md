# Homelab monorepo agent guide

- **Layout**: `ansible/` (host config, formerly homelab-ansible), `tofu/` (OpenTofu VM provisioning, formerly homelab-tofu), `docs/` (design notes like `docs/dns-plan.md`).
- **Make wrappers**: From repo root use `make ansible-<target>` and `make tofu-<target>` to call component Makefiles (see `make ansible-help`, `make tofu-help`). Avoid running `ansible-playbook` or `tofu` directly; prefer the Dockerized targets.
- **Containerized workflows**: Both stacks expect Docker/Compose; use provided Make targets for build/plan/apply/lint. Keep secrets in local `.env` files (gitignored) and never commit keys or state.
- **DNS direction**: We standardized on NSD as the authoritative server (`lan.quietlife.net`), with Unbound on the firewall as recursive + stub to NSD. DHCP/DNS should be driven from a shared data model; include an `dhcp-<nn>.lan.quietlife.net` pool for ephemeral clients. See `docs/dns-plan.md`.
- **Host data**: Inventories and templates live under `ansible/` (e.g., `inventories/hosts.yml`, `roles/openbsd_firewall`). Keep DHCP reservations, DNS records, and VM definitions consistent by editing shared host metadata when adding nodes.
- **Testing/validation**: Run relevant Dockerized checks before changes: `make ansible-trufflehog`, `make tofu-validate/plan`, `make ansible-ping`/`ansible-firewall` dry runs as needed. Keep changes scoped; avoid large “deploy everything” unless required.
- **No destructive ops**: Don’t use sudo; avoid wiping state or force pushes. If you must propose a destructive command, surface it to the user instead of running it.
