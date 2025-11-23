# Packages Role

Installs a predefined list of system packages on Debian/Ubuntu hosts using the APT package manager.

## Purpose

This role provides a simple way to ensure common system packages are installed across all managed hosts. It's designed for packages that should be present on every server before other roles or applications are deployed.

## Requirements

- **Target OS**: Debian/Ubuntu Linux (uses APT)
- **Privileges**: Requires `become: true` (sudo/root access)
- **Network**: Internet access or local APT mirror
- **Python**: Python 3 on target hosts

## Role Variables

### Required Variables

This role expects `system_packages` to be defined, typically in inventory group variables.

### Example Variables

In `inventories/group_vars/all.yml` or `inventories/group_vars/<group>.yml`:

```yaml
---
system_packages:
  - curl
  - vim
  - git
  - htop
  - tmux
  - net-tools
  - build-essential
```

## Dependencies

None. This is a standalone role.

## Example Usage

### Basic Playbook

```yaml
---
- name: Install system packages
  hosts: all
  become: true
  roles:
    - packages
```

### Example Inventory Configuration

In `inventories/group_vars/proxmox.yml`:

```yaml
---
system_packages:
  - curl
  - vim
  - git
  - htop
  - tmux
  - qemu-guest-agent  # Proxmox-specific
  - open-iscsi
```

In `inventories/group_vars/linode_vps.yml`:

```yaml
---
system_packages:
  - curl
  - vim
  - git
  - htop
  - tmux
  - fail2ban  # VPS-specific security
  - ufw
```

### Running the Role

```bash
# Apply via playbooks that include this role
ansible-playbook playbooks/vps.yml -vv
```

Or include it in your playbook:
```yaml
---
- name: Configure VPS
  hosts: linode_vps
  become: true
  roles:
    - packages
    - system
    - users
```

## What This Role Does

### 1. Update APT Cache

- Runs `apt update` to refresh package lists
- Ensures latest package versions are available
- Equivalent to: `apt-get update`

### 2. Install Packages

- Installs all packages in `system_packages` list
- Uses APT package manager
- Idempotent: skips already installed packages
- Equivalent to: `apt-get install <package>`

## Outputs

After running this role:
- All packages in `system_packages` are installed
- APT cache is up to date
- Packages are at their latest available version (if previously installed)

## Assumptions and Limitations

### Assumptions
- Target systems use APT (Debian/Ubuntu family)
- Package names match APT repository packages
- Internet access or configured APT mirrors are available

### Limitations
- Does not remove packages
- Does not pin package versions
- Does not add third-party repositories
- Does not configure packages (just installs them)
- Not suitable for OpenBSD or other non-Debian systems

### Design Philosophy

This role is intentionally simple:
- ✅ Install common packages
- ✅ Keep list in inventory (visible and version-controlled)
- ❌ No complex package management
- ❌ No version pinning (use OS defaults)

For complex package needs, consider the `custom_packages` role or dedicated application roles.

## Integration with Other Roles

Typical role order:
1. **Packages role**: Install system-wide utilities
2. **System role**: Configure hostname, SSH
3. **Users role**: Create users
4. **Application roles**: Deploy services

## Common Packages

### Base Utilities
```yaml
system_packages:
  - curl          # HTTP client
  - wget          # File downloader
  - vim           # Text editor
  - nano          # Simple editor
  - git           # Version control
```

### Monitoring & Debugging
```yaml
system_packages:
  - htop          # Process viewer
  - iotop         # I/O monitor
  - nethogs       # Network monitor per process
  - tcpdump       # Packet capture
  - strace        # System call tracer
```

### Network Tools
```yaml
system_packages:
  - net-tools     # ifconfig, netstat
  - iproute2      # ip command
  - dnsutils      # dig, nslookup
  - traceroute    # Network path tracing
  - netcat        # Network Swiss Army knife
```

### Development
```yaml
system_packages:
  - build-essential  # gcc, make, etc.
  - python3-pip      # Python package manager
  - python3-venv     # Python virtual environments
```

### Proxmox-Specific
```yaml
system_packages:
  - qemu-guest-agent  # VM integration
  - open-iscsi        # iSCSI support
```

### Security
```yaml
system_packages:
  - fail2ban      # Brute force protection
  - ufw           # Firewall
  - unattended-upgrades  # Auto security updates
```

## Common Issues

**"Package not found":**
- Verify package name: `apt-cache search <package>`
- Check package exists in your Ubuntu/Debian version
- Update package lists: `apt update`

**"Unable to locate package":**
- Package may be in a different repository
- Check if repository is enabled
- Consider adding PPA or third-party repo (not in this role)

**Package installation fails:**
- Check logs: `journalctl -u apt`
- Verify disk space: `df -h`
- Check for conflicting packages
- Run with verbose mode: `-vvv`

**"Hash Sum mismatch" errors:**
- APT cache corruption
- Run: `apt-get clean && apt-get update`
- May indicate network/proxy issues

## Testing

```bash
# Check if packages are installed
ansible all -l pve1 -m shell -a "dpkg -l | grep curl"
ansible all -l pve1 -m shell -a "which vim"

# Verify with package module
ansible all -l pve1 -m package -a "name=curl state=present" --check

# Install missing packages
ansible all -l pve1 -m apt -a "name=htop state=present update_cache=yes" --become
```

## Advanced Usage

### Conditional Package Installation

For packages that should only be installed on certain hosts:

```yaml
# inventories/host_vars/pve1.yml
system_packages:
  - curl
  - vim
  - "{{ 'qemu-guest-agent' if ansible_virtualization_type == 'kvm' else '' }}"
```

Or use separate group variables:

```yaml
# inventories/group_vars/virtual_machines.yml
vm_packages:
  - qemu-guest-agent

# In playbook
- name: Install VM-specific packages
  ansible.builtin.apt:
    name: "{{ vm_packages }}"
    state: present
  when: ansible_virtualization_type == 'kvm'
```

### Combined Package Lists

```yaml
# inventories/group_vars/all.yml
base_packages:
  - curl
  - vim
  - git

# inventories/group_vars/proxmox.yml
system_packages: "{{ base_packages + proxmox_packages }}"

proxmox_packages:
  - qemu-guest-agent
  - open-iscsi
```

## Related Roles

- **custom_packages**: For role-specific package installation logic
- **system**: System configuration (runs after packages)
- **users**: User management (runs after packages)

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial setup
- [Custom Packages Role](../custom_packages/README.md) — Advanced package management
- [APT Documentation](https://wiki.debian.org/Apt) — Package manager details
