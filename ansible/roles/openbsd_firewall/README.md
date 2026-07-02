# OpenBSD Firewall Role

This role manages pf.conf, dhcpd.conf, and unbound DNS resolver on OpenBSD firewalls.

## Prerequisites

### doas Configuration

The deploy user requires elevated privileges to manage firewall services. The current `/etc/doas.conf` configuration:

```conf
permit persist :wheel
permit persist deploy as root
```

This allows the deploy user to run privileged commands with password authentication. The playbook uses `become: true` for tasks that require root access.

**Note**: `/etc/doas.conf` is manually managed and not controlled by Ansible to prevent privilege escalation issues.

## What This Role Does

1. **PF Configuration** (`roles/openbsd_firewall/tasks/pf.yml`)
   - Renders `pf.conf.j2` template
   - Writes to `/tmp/pf.conf.new`
   - Validates with `pfctl -nf`
   - Deploys to `/etc/pf.conf` if validation passes
   - Reloads PF firewall

2. **DHCP Configuration** (`roles/openbsd_firewall/tasks/dhcpd.yml`)
   - Renders `dhcpd.conf.j2` template
   - Writes to `/tmp/dhcpd.conf.new`
   - Validates with `dhcpd -n -c`
   - Deploys to `/etc/dhcpd.conf` if validation passes
   - Enables and restarts dhcpd service

3. **Unbound DNS Resolver** (`roles/openbsd_firewall/tasks/unbound.yml`)
   - Installs unbound package if not present
   - Renders `unbound.conf.j2` template
   - Writes to `/tmp/unbound.conf.new`
   - Validates with `unbound-checkconf`
   - Deploys to `/var/unbound/etc/unbound.conf` if validation passes
   - Enables and starts unbound service
   - Full recursive resolver (no upstream forwarders) with DNSSEC validation
   - Bootstraps the DNSSEC root trust anchor (`/var/unbound/db/root.key`) via `unbound-anchor` and keeps it owned by `_unbound` for RFC 5011 rollover
   - Stub zones delegate `lan.quietlife.net` and `15.10.10.in-addr.arpa` to NSD on dns1

4. **Resolv.conf Management** (`roles/openbsd_firewall/tasks/resolv.yml`)
   - Configures firewall's own DNS resolution
   - Sets nameserver to localhost (127.0.0.1) to use local Unbound
   - Fallback to upstream resolver (Cloudflare 1.1.1.1)
   - Deploys to `/etc/resolv.conf`

## Usage

```bash
# Deploy all firewall services (pf, dhcp, and unbound)
ansible-playbook playbooks/firewall.yml

# Deploy only pf config
ansible-playbook playbooks/firewall.yml --tags pf

# Deploy only dhcp config
ansible-playbook playbooks/firewall.yml --tags dhcpd

# Deploy only unbound DNS config
ansible-playbook playbooks/firewall.yml --tags unbound

# Or using the Makefile (runs in Docker)
make firewall
```

## Configuration Variables

### Unbound DNS Resolver

Default variables are defined in `roles/openbsd_firewall/defaults/main.yml`:

```yaml
# Unbound DNS resolver configuration
unbound_conf_path: /var/unbound/etc/unbound.conf
unbound_port: 53

# Interfaces for Unbound to listen on
unbound_listen_interfaces:
  - 127.0.0.1
  - 10.10.15.1  # LAN interface
  - 10.10.16.1  # WireGuard VPN interface

# Networks allowed to query DNS
unbound_access_control:
  - 127.0.0.0/8
  - 10.10.15.0/24  # LAN network
  - 10.10.16.0/24  # WireGuard VPN network

# Emergency fallback resolver for fw1's own resolv.conf, used only when the
# local Unbound is down (e.g. during a restart)
resolv_fallback_nameserver: 1.1.1.1
```

These can be overridden in `group_vars/openbsd_firewalls.yml` or host-specific variables.

### DNS Configuration Summary

- **DHCP clients** (LAN): Receive `10.10.15.1` as their DNS server via DHCP
- **Firewall itself**: Uses localhost (127.0.0.1) with `resolv_fallback_nameserver` (1.1.1.1) as an emergency second entry, only consulted when local Unbound is down
- **WireGuard clients**: Must manually add `DNS = 10.10.16.1` to their client config
- **External names**: Resolved by full recursion from the root servers with DNSSEC validation — no upstream forwarder dependency (see issue #263)
- **Local zones**: `lan.quietlife.net` and `15.10.10.in-addr.arpa` are stub zones pointing at NSD on dns1 (10.10.15.15); a `transparent` local-zone for `15.10.10.in-addr.arpa` overrides unbound's builtin RFC 6303 empty zone so reverse lookups reach the stub

## Safety Features

- All configurations are validated before deployment
- Invalid configurations will fail the playbook without making changes
- Uses temporary files to avoid corrupting live configs
- No Python required on the OpenBSD host (uses `raw` module)
