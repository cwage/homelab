# ansible — host configuration

Ansible roles and playbooks for configuring all homelab hosts: Proxmox hypervisor, OpenBSD firewall, DNS server, Docker container host, NAS, and VPS instances. All operations run inside Docker containers.

## Setup

Ansible reads credentials from the root `.env` file (shared with OpenTofu). See the root [README](../README.md) getting-started section for initial `.env` setup.

```bash
make init          # set UID/GID in .env for Docker user mapping
make build         # build the Ansible Docker image
make galaxy        # install required Ansible collections
make ping          # test connectivity to all hosts
```

### SSH keys

Two separate key directories:

- **`keys/`** — Deploy key for Ansible automation (`keys/deploy` private, `keys/deploy.pub` public). The private key is gitignored.
- **`inventories/keys/`** — User SSH public keys deployed to hosts via the `users` role.

## Common commands

```bash
make ping                     # test connectivity
make firewall                 # configure fw1 (pf, DHCP, Unbound, WireGuard)
make firewall-check           # dry-run firewall
make containers               # configure containers host (Docker, GPU, certs, stacks)
make proxmox                  # configure pve1 (users, NFS mounts)
make felix                    # configure VPS
make gaming                   # provision game servers
make all                      # apply all standard playbooks (use sparingly)
make run PLAY=playbooks/firewall.yml LIMIT=fw1 OPTS="--check --diff"
make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'
make sh                       # interactive shell in Ansible container
```

Run `make help` for the full list.

## Validation and collection updates

From the repo root:

```bash
make ansible-check             # same collection and syntax checks as CI
make ansible-galaxy            # install reviewed pins into the local collections/ directory
```

`requirements.yml` pins every collection to an exact version. Renovate opens
weekly update PRs, grouping minor/patch updates and keeping majors separate.

`requirements.txt` separately pins the controller runtime (Ansible Core 2.21.4
and `hvac`), also tracked by Renovate. The Dockerfile uses Debian trixie for
Python 3.13. Core 2.21 supports controller Python 3.12–3.14 and target Python
3.9–3.14; the firewall and NAS roles use raw SSH commands without remote Python.
See the [Core support matrix](https://docs.ansible.com/projects/ansible/latest/reference_appendices/release_and_maintenance.html#ansible-core-support-matrix).

Core's X.Y releases can introduce breaking changes even though Renovate calls
them minor updates. Review the relevant
[porting guides](https://docs.ansible.com/projects/ansible/latest/porting_guides/core_porting_guides.html),
particularly the stricter conditionals and templating introduced in 2.19.
Renovate keeps Core patch updates separate from X.Y upgrades.

The collection pins remain separate: a runtime upgrade does not approve a
collection upgrade. General 12.x and hashi_vault 7.x require Core 2.17+, while
General 13.x requires Core 2.18+. After merging a runtime prerequisite, request
a rebase on the collection PRs so CI tests them against the new runtime.

`make ansible-check` builds from the same Dockerfile as the deploy container,
installs collections fresh inside a disposable container, checks the modules,
lookup, and become plugins used here, and syntax-checks all playbooks.
It also renders firewall templates on localhost with fixture data to exercise
the controller's template lookup behavior without contacting a host.
Unsupported `requires_ansible` metadata fails the check. It bypasses the
OpenBao preflight and needs no `.env`, SSH key, or running homelab. The check
mounts only the playbooks, roles, tests, host inventory, and validation configuration;
collections and temporary files stay inside the container.

This validates collection installation, plugin loading, static playbook
syntax, and the template fixtures. It does not execute host tasks, evaluate
secret lookups, or exercise dynamic task includes and host-specific variables.
Relevant host dry runs and manual review are still needed before deploying an update.

After merging a runtime change and pulling it locally, rebuild the deploy
image with `make ansible-build`, then install the reviewed collections with
`make ansible-galaxy`. The disposable CI image is separate from the deploy
image, so `make ansible-check` alone does not update the tooling used for host
operations. These commands prepare local tooling; host playbooks remain a
separate, manual step.

## Inventory

Hosts and groups defined in `inventories/hosts.yml`. Group variables in `inventories/group_vars/`, host-specific overrides in `inventories/host_vars/`.

| Group | Hosts | Playbook |
|-------|-------|----------|
| `proxmox` | pve1 | `playbooks/proxmox.yml` |
| `openbsd_firewalls` | fw1 | `playbooks/firewall.yml` |
| `linode_vps` | felix | `playbooks/vps.yml` |
| `gaming_servers` | gaming1 | `playbooks/gaming.yml` |

`portanas` (Synology NAS) is a standalone host managed via `playbooks/nas.yml`.

## Roles

| Role | Description |
|------|-------------|
| `users` | System users, SSH keys, sudo, home directories |
| `openbsd_firewall` | pf, dhcpd, unbound, resolv.conf (OpenBSD, raw module) |
| `wireguard_server` | WireGuard VPN on OpenBSD |
| `gpu_passthrough` | VFIO/IOMMU on Proxmox for PCI passthrough |
| `dns_client` | /etc/resolv.conf configuration |
| `packages` | System packages from variable list |
| `custom_packages` | Custom .deb packages (tinyfugue) |
| `nfs_mounts` | Client-side NFS mount configuration |
| `synology_nfs` | Manage NFS shares on Synology DSM via SSH |
| `proxmox_certs` | Deploy wildcard TLS cert to Proxmox |
| `nginx` | Install nginx, manage www-data group |
| `hostname` | Set hostname and /etc/hosts |
| `system` | Hostname, /etc/hosts, SSH socket config |
| `gaming_server` | LinuxGSM game server management |
| `pve_template` | Build Proxmox VM templates |

## Docker workflow

The Ansible container runs with `network_mode: host` so it can reach LAN hosts directly. It mounts the repo at `/work` and passes through OpenBao credentials from the root `.env` via `--env-file`.

```bash
make build            # rebuild the container image
make version          # show Ansible version in container
make sh               # interactive shell for debugging
```

## Secret scanning

```bash
make trufflehog       # scan ansible/ tree for leaked secrets
```

## OpenBSD notes

The `openbsd_firewall` and `wireguard_server` roles use `ansible.builtin.raw` exclusively — Python is deliberately not installed on the firewall for hardening. Configs are validated before deployment (`pfctl -nf`, `dhcpd -n`, `nsd-checkconf`) and services are reloaded via handlers.
