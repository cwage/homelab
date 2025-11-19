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
   - Configured as a forwarding resolver (forwards to Cloudflare DNS by default)
   - Includes placeholder for future stub-zone configuration for `lan.quietlife.net`

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

# Upstream DNS forwarders (Cloudflare)
unbound_forwarders:
  - 1.1.1.1
  - 1.0.0.1
```

These can be overridden in `group_vars/openbsd_firewalls.yml` or host-specific variables.

### DNS Configuration Summary

- **DHCP clients** (LAN): Receive `10.10.15.1` as their DNS server via DHCP
- **Firewall itself**: Uses localhost (127.0.0.1) with fallback to Cloudflare
- **WireGuard clients**: Must manually add `DNS = 10.10.16.1` to their client config
- **Upstream forwarders**: Unbound forwards queries to Cloudflare (1.1.1.1, 1.0.0.1)

### Future: Stub Zone for Local Domain

The Unbound configuration includes a commented-out stub zone section for `lan.quietlife.net`. When you're ready to set up an authoritative bind instance for your local domain, uncomment and configure:

```yaml
# In unbound.conf.j2
stub-zone:
    name: "lan.quietlife.net"
    stub-addr: <bind-server-ip>
```

## Safety Features

- All configurations are validated before deployment
- Invalid configurations will fail the playbook without making changes
- Uses temporary files to avoid corrupting live configs
- No Python required on the OpenBSD host (uses `raw` module)
