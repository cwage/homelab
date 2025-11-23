# Ansible Inventory Guide

This guide explains how to structure and configure the Ansible inventory for the homelab.

## Overview

The inventory defines which hosts Ansible manages and how to connect to them. It uses YAML format and supports hierarchical group/host variable definitions.

## Directory Structure

```
ansible/inventories/
├── hosts.yml              # Main inventory file (host definitions)
├── group_vars/
│   ├── all.yml           # Variables for all hosts
│   ├── proxmox.yml       # Variables for proxmox group
│   ├── openbsd_firewalls.yml  # Variables for firewall group
│   └── linode_vps.yml    # Variables for VPS group
└── host_vars/
    ├── pve1.yml          # Host-specific variables for pve1
    ├── fw1.yml           # Host-specific variables for fw1
    ├── felix.yml         # Host-specific variables for felix
    └── portanas.yml      # Host-specific variables for NAS
```

## Main Inventory File

`inventories/hosts.yml` defines hosts and groups:

```yaml
all:
  children:
    # Proxmox VE hosts
    proxmox:
      hosts:
        pve1:
          ansible_host: 10.10.15.18
          ansible_port: 22
    
    # OpenBSD firewall hosts
    openbsd_firewalls:
      hosts:
        fw1:
          ansible_host: 10.10.15.1
          ansible_port: 22
    
    # Linode VPS hosts
    linode_vps:
      hosts:
        felix:
          ansible_host: 45.56.113.70
          ansible_port: 5344
  
  # Ungrouped hosts (directly under 'all')
  hosts:
    portanas:
      ansible_host: 10.10.15.4
      ansible_port: 5344
      ansible_user: deploy
```

## Connection Variables

### Per-Host Connection Settings

In `hosts.yml`, each host supports:

```yaml
hosts:
  hostname:
    ansible_host: 10.10.15.18      # IP address or FQDN
    ansible_port: 22                # SSH port (default: 22)
    ansible_user: deploy            # SSH user (default: from ansible.cfg)
    ansible_python_interpreter: /usr/bin/python3  # Python path (auto-discovered)
```

### Global Connection Settings

Defined in `ansible.cfg`:

```ini
[defaults]
remote_user = deploy
private_key_file = keys/deploy/id_ed25519
host_key_checking = False  # Disable for bootstrap convenience
```

## Group Variables

Group variables apply to all hosts in a group. Defined in `inventories/group_vars/<group>.yml`.

### Example: `group_vars/all.yml`

Variables for all hosts:

```yaml
---
# Domain name for FQDN construction
domain_name: quietlife.net

# SSH ports for systemd socket configuration
ssh_ports:
  - 443
  - 5344

# System packages to install on all hosts
system_packages:
  - curl
  - vim
  - git
  - htop
  - tmux
```

### Example: `group_vars/proxmox.yml`

Variables specific to Proxmox hosts:

```yaml
---
# Users to manage on Proxmox hosts
managed_users:
  - name: deploy
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/deploy.pub"
  
  - name: cwage
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/cwage.pub"

# Template definitions for pve_template role
pve_templates:
  - name: debian12-template
    vmid: 9000
    image_file: debian-12-genericcloud-amd64.img
    datastore: local-lvm
    bridge: vmbr0
    memory: 2048
    cores: 2
    ciuser: deploy
    fqdn: debian12-template.lan.quietlife.net
```

### Example: `group_vars/openbsd_firewalls.yml`

Variables for OpenBSD firewall hosts:

```yaml
---
# Unbound DNS resolver interfaces
unbound_listen_interfaces:
  - 127.0.0.1
  - 10.10.15.1  # LAN
  - 10.10.16.1  # VPN

# Networks allowed to query DNS
unbound_access_control:
  - 127.0.0.0/8
  - 10.10.15.0/24  # LAN
  - 10.10.16.0/24  # VPN

# Upstream DNS forwarders
unbound_forwarders:
  - 1.1.1.1
  - 1.0.0.1
```

## Host Variables

Host-specific variables override group variables. Defined in `inventories/host_vars/<hostname>.yml`.

### Example: `host_vars/fw1.yml`

WireGuard configuration for firewall:

```yaml
---
# WireGuard VPN peers
wireguard_peers:
  - name: laptop
    public_key: "AbCd...1234=="
    allowed_ips: "10.10.16.2/32"
    persistent_keepalive: 0
  
  - name: phone
    public_key: "EfGh...5678=="
    allowed_ips: "10.10.16.3/32"
    persistent_keepalive: 0
```

### Example: `host_vars/felix.yml`

Nginx sites for VPS:

```yaml
---
# Override SSH ports for this host
ssh_ports:
  - 22
  - 5344

# Nginx virtual hosts
nginx_sites:
  - server_name: tmp.quietlife.net
    root: /var/www/tmp.quietlife.net
    owner: cwage
    group: cwage
    dir_mode: '0750'
    file_mode: '0640'
  
  - server_name: books.quietlife.net
    root: /var/www/books.quietlife.net
    owner: cwage
    group: cwage
    dir_mode: '0750'
    file_mode: '0640'
    basic_auth:
      realm: "Books"
      users:
        - username: books
          password_hash: "$apr1$..."
```

### Example: `host_vars/portanas.yml`

NFS shares for Synology NAS:

```yaml
---
# NFS share configurations
nfs_shares:
  - name: pve-backups
    description: "Proxmox backup storage"
    path: /volume1/pve-backups
    nfs_enabled: true
    nfs_rules:
      - host: "10.10.15.0/24"
        privilege: "rw"
        squash: "no_root_squash"
        security: "sys"
```

## Variable Precedence

Ansible resolves variables in this order (highest to lowest priority):

1. Extra vars (`-e` flag or `extra_vars:` in playbook)
2. Task vars
3. Block vars
4. Role vars (defined in role's `vars/main.yml`)
5. Play vars
6. **Host vars** (`host_vars/<hostname>.yml`) ← Common override location
7. **Group vars** (`group_vars/<group>.yml`)
8. Role defaults (defined in role's `defaults/main.yml`)

**Rule of thumb:**
- Use role `defaults/main.yml` for sensible defaults
- Use `group_vars/` for environment-wide settings
- Use `host_vars/` for host-specific overrides

## Common Inventory Patterns

### Multiple Environments

For dev/staging/prod:

```
inventories/
├── dev/
│   ├── hosts.yml
│   └── group_vars/
├── staging/
│   ├── hosts.yml
│   └── group_vars/
└── production/
    ├── hosts.yml
    └── group_vars/
```

Use with: `ansible-playbook -i inventories/dev/hosts.yml playbook.yml`

### Dynamic Groups

Create groups based on variables:

```yaml
# In group_vars/all.yml
environments:
  dev: [dev-vm1, dev-vm2]
  prod: [prod-vm1, prod-vm2]

# Use in playbook
- hosts: "{{ environments.dev }}"
```

### Host Aliases

Use friendly names with real IPs:

```yaml
all:
  hosts:
    web:
      ansible_host: 192.168.1.10
    db:
      ansible_host: 192.168.1.20
    cache:
      ansible_host: 192.168.1.30
```

## Security Best Practices

### Sensitive Variables

**Don't commit sensitive values to git!**

Options:
1. **Ansible Vault**: Encrypt sensitive files
   ```bash
   ansible-vault encrypt inventories/group_vars/all/vault.yml
   ansible-playbook playbook.yml --ask-vault-pass
   ```

2. **External secrets**: Store in password manager, inject at runtime
   ```bash
   ansible-playbook playbook.yml -e "api_key=$(pass homelab/api_key)"
   ```

3. **Environment variables**: Read from shell
   ```yaml
   api_key: "{{ lookup('env', 'API_KEY') }}"
   ```

### SSH Key Management

- ✅ Store private keys in `keys/` (gitignored)
- ✅ Reference public keys in inventory
- ✅ Use different keys per environment
- ❌ Never commit private keys

### Access Control

```yaml
# Limit sudo access
managed_users:
  - name: developer
    shell: /bin/bash
    groups: []  # No sudo
    sudo_nopasswd: false
    ssh_pubkey_file: "keys/developer.pub"
```

## Testing Inventory

### List All Hosts

```bash
ansible all --list-hosts
```

### Show Host Variables

```bash
ansible-inventory --host pve1 --yaml
```

### List Groups

```bash
ansible-inventory --graph
```

Example output:
```
@all:
  |--@openbsd_firewalls:
  |  |--fw1
  |--@proxmox:
  |  |--pve1
  |--@ungrouped:
  |  |--portanas
```

### Test Connectivity

```bash
# Test all hosts
make ping

# Test specific group
ansible proxmox -m ping

# Test specific host
ansible -m ping pve1
```

## Common Issues

**"Host not found":**
- Check spelling in `hosts.yml`
- Verify host is in correct group
- Run: `ansible all --list-hosts`

**"Unreachable" or "Connection refused":**
- Verify `ansible_host` IP/hostname
- Check `ansible_port` if using non-standard port
- Test SSH manually: `ssh -p <port> deploy@<host>`
- Check firewall rules

**Variables not applying:**
- Check variable precedence (host_vars beats group_vars)
- Verify file names match hostname/group exactly
- Use: `ansible-inventory --host <hostname> --yaml` to debug
- Check for typos in variable names

**"No hosts matched":**
- Ensure host/group exists in inventory
- Check playbook `hosts:` pattern
- Use `-l` to limit: `ansible-playbook playbook.yml -l pve1`

## Related Documentation

- [Getting Started Guide](../../docs/getting-started.md) — Initial setup
- [Ansible Configuration](../ansible.cfg) — Global Ansible settings
- [Official Ansible Inventory Docs](https://docs.ansible.com/ansible/latest/user_guide/intro_inventory.html)
