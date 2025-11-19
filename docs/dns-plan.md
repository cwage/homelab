# Authoritative DNS plan for `lan.quietlife.net`

## Goals and constraints
- Use `lan.quietlife.net` for all internal hosts (static fixtures and more ephemeral DHCP clients).
- Keep DNS and DHCP in sync; avoid duplicating host data across templates.
- Firewall stays the recursive resolver for LAN/VPN; it should stub only `lan.quietlife.net` to the authoritative server.
- Outage of the authoritative host must not break normal Internet lookups; only the local zone should be affected if it goes away.

## Current state
- Firewall (OpenBSD) runs ISC `dhcpd` and Unbound via Ansible role `roles/openbsd_firewall` (`dhcpd.conf.j2`, `unbound.conf.j2`). Unbound already has a commented stub block for `lan.quietlife.net`.
- DHCP hands out 10.10.15.0/24 with static fixtures listed directly in the template; WireGuard VPN uses 10.10.16.0/24.
- homelab-tofu currently has only the Proxmox provider scaffold—no DNS VM resource yet.

## Proposed design
- **Authoritative service**: Create a dedicated VM (e.g., `dns1`) on Proxmox running NSD (authoritative-only). No recursion enabled. Static IP on 10.10.15.0/24 with a matching PTR.
- **Data model for parity**: Introduce a single Ansible data structure (e.g., `inventories/group_vars/lan_hosts.yml`) describing hosts with name, MAC, IP (or pool assignment), and record metadata. Generate both `dhcpd.conf` and NSD zone files from this source to keep DHCP reservations and DNS records aligned.
- **Zones**: Serve `lan.quietlife.net` and reverse `15.10.10.in-addr.arpa` (and `16.10.10.in-addr.arpa` if we want PTRs for VPN addresses). Include A/AAAA/PTR for static fixtures, and optionally TXT/SRV for services (Proxmox UI, VPN endpoints, etc.). Reserve a DHCP “ephemeral” pool with predictable generic names (e.g., `dhcp-<nn>.lan.quietlife.net`) for short-lived hosts; these can be template-generated rather than individually named.
- **DHCP integration**: Update `dhcpd.conf` to set `domain-name "lan.quietlife.net"` and keep issuing the firewall address as the resolver. Keep DDNS off initially; rely on the shared data model and templated outputs for both DHCP reservations and DNS zones, including the generic ephemeral pool if desired.
- **Firewall resolver changes**: Enable the stub-zone in `unbound.conf.j2` pointing to `dns1`; keep Cloudflare forwarders for everything else so Internet resolution is unaffected by a `dns1` outage. Optionally add a handful of critical `local-data` fallbacks for emergency resolution if the stub target is down.
- **Resilience and ops**: Optionally add a secondary (NSD on the firewall or another VM) and allow zone transfers from `dns1`. Keep TTLs modest (e.g., 300s) while iterating, add `nsd-checkconf`/`nsd-checkzone` validation in Ansible, and back up zone data/keys.

## Implementation steps
1) **Model host inventory**: Extract the static fixtures from `roles/openbsd_firewall/templates/dhcpd.conf.j2`, dedupe entries, and move them into a shared `lan_hosts` var. Define the reserved DHCP pool and naming pattern for ephemeral clients (`dhcp-<nn>.lan.quietlife.net`) that can be auto-rendered without per-host entries.
2) **Provision the VM**: Extend homelab-tofu to create `dns1` with a static NIC on the LAN bridge (and optional mgmt/VPN NIC if desired). Allocate CPU/RAM/disk, cloud-init user, and SSH keys consistent with other VMs.
3) **Authoritative role**: Add an Ansible role to install and configure NSD, manage zone files from templates fed by `lan_hosts` (including the ephemeral pool), set TSIG keys for zone transfers (and future DDNS if we ever enable it), and expose TCP/UDP 53.
4) **DHCP + resolver wiring**: Regenerate `dhcpd.conf` from the shared data, switch the `domain-name` to `lan.quietlife.net`, generate the ephemeral pool entries, and enable the Unbound stub-zone to `dns1`. Keep upstream forwarders as-is for non-local queries.
5) **Testing and rollout**: Validate configs with `nsd-checkconf`/`nsd-checkzone` (or `nsd-control checkconf`) plus `unbound-checkconf`, and run `dig` for A/PTR/SOA/NS locally on `dns1`, then through the firewall. Test failure mode by blocking `dns1` and confirming Internet lookups still work while `lan.quietlife.net` fails cleanly.
6) **Ops polish**: Add monitoring (service health, zone serial drift), snapshot/backup strategy for zone+keys, and document how to add/change hosts so DHCP/DNS stay in lockstep.

## Open questions
- What static IP should `dns1` use on 10.10.15.0/24, and do we also want it on the VPN subnet for roaming management?
- If we ever revisit DDNS, what criteria would justify it vs. keeping the static + reserved-pool model (note: would require revisiting BIND or another DDNS-capable daemon)?
- How large should the reserved `dhcp-<nn>` pool be, and do we want both forward and PTRs for those generics?
- Should we stand up a secondary right away (e.g., NSD on the firewall) or defer until after the primary is stable?
