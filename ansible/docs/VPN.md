# WireGuard VPN

This was the original design document for the WireGuard VPN setup. The implementation is complete and the operational documentation now lives in the role README:

**[ansible/roles/wireguard_server/README.md](../roles/wireguard_server/README.md)**

That covers setup instructions, key management, client configuration (including Android QR codes), firewall integration, testing, and troubleshooting.

## Architecture summary

- **Hub-and-spoke** topology with fw1 as the hub
- **VPN subnet**: 10.10.16.0/24 (LAN is 10.10.15.0/24)
- **Split-tunnel only** — clients route only homelab traffic through VPN
- **No NAT** — fw1 is already the LAN gateway, so return routing works naturally
- **OpenBSD native** — uses the kernel `wg(4)` driver, configured via `hostname.wg0`

## Key decisions

- Custom UDP port (51923) for obscurity
- Private keys generated on target hosts, never stored in the repo
- Public keys stored in Ansible vars (`host_vars/fw1.yml`)
- Split-tunnel by design — only 10.10.15.0/24 and 10.10.16.0/24 routed through VPN
