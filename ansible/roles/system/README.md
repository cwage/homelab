# System Role

Configures basic system settings including hostname, SSH service configuration, and hosts file management.

## Purpose

This role handles foundational system configuration that should be applied early in the host setup process. It sets the system hostname, configures multi-port SSH listening via systemd socket activation, and manages `/etc/hosts` entries.

## Requirements

- **Target OS**: Debian/Ubuntu Linux with systemd
- **Privileges**: Requires `become: true` (sudo/root access)
- **Services**: systemd (for socket-based SSH configuration)
- **Python**: Python 3 on target hosts

## Role Variables

### Optional Variables (with defaults)

Defined in `defaults/main.yml`:

```yaml
# Domain name for FQDN construction
domain_name: quietlife.net

# SSH ports to listen on (via socket activation)
ssh_ports:
  - 443
  - 5344
```

### Variable Usage

- `domain_name`: Combined with `inventory_hostname_short` to create FQDN
- `ssh_ports`: List of ports for SSH to listen on (replaces standard port 22)

**Note**: If `domain_name` is undefined, hostname configuration is skipped.

## Dependencies

None. This is a standalone role.

## Example Usage

### Basic Playbook

```yaml
---
- name: Configure system basics
  hosts: all
  become: true
  roles:
    - system
```

### Example Inventory Configuration

In `inventories/group_vars/all.yml`:

```yaml
---
domain_name: quietlife.net

ssh_ports:
  - 443      # HTTPS port (bypass some firewalls)
  - 5344     # Custom high port
```

Or in `inventories/host_vars/felix.yml` for a specific host:

```yaml
---
ssh_ports:
  - 22       # Standard port for VPS
  - 5344     # Additional port
```

### Running the Role

```bash
# Apply via a playbook that includes the system role
ansible-playbook playbooks/vps.yml -vv
```

## What This Role Does

### 1. Set System Hostname

- Constructs FQDN as `<inventory_hostname_short>.<domain_name>`
- Uses `ansible.builtin.hostname` module
- Only runs if `domain_name` is defined
- Example: Inventory host `felix` becomes `felix.quietlife.net`

### 2. Update /etc/hosts

- Adds entry: `127.0.1.1  <fqdn> <hostname>`
- Updates existing `127.0.1.1` line if present
- Ensures hostname resolves locally
- Only runs if `domain_name` is defined

Example `/etc/hosts` entry:
```
127.0.1.1	felix.quietlife.net felix
```

### 3. Configure Multi-Port SSH (systemd socket)

Creates systemd socket override for SSH to listen on multiple ports:

**Creates directory:**
- `/etc/systemd/system/ssh.socket.d/`

**Creates override file:**
- `/etc/systemd/system/ssh.socket.d/override.conf`

**Override content example:**
```ini
[Socket]
ListenStream=
ListenStream=0.0.0.0:443
ListenStream=[::]:443
ListenStream=0.0.0.0:5344
ListenStream=[::]:5344
```

**Note**: The empty `ListenStream=` clears the default port 22.

### 4. Reload systemd and Enable Services

- Reloads systemd daemon to pick up socket changes
- Enables `ssh.socket` if not already enabled
- Stops and disables legacy `ssh.service` (socket takes precedence)
- Starts/restarts `ssh.socket` with new configuration

## Outputs

After running this role:
- Hostname is set to FQDN
- `/etc/hosts` contains correct FQDN entry
- SSH listens on all configured ports (both IPv4 and IPv6)
- SSH uses systemd socket activation
- Legacy SSH service is disabled in favor of socket

## Assumptions and Limitations

### Assumptions
- Target system uses systemd (Debian 8+, Ubuntu 15.04+)
- SSH is installed via package `openssh-server`
- Socket activation is preferred over traditional service
- IPv6 is available (creates IPv6 listeners)

### Limitations
- Does not configure SSH daemon settings (sshd_config)
- Does not manage SSH host keys
- Does not configure firewall rules for new SSH ports
- IPv6 listeners created even if IPv6 is disabled (harmless)

### Why Socket Activation?

Socket activation (systemd) vs. traditional SSH service:
- ✅ More flexible port configuration
- ✅ Easier to manage multiple ports
- ✅ On-demand service startup (optional)
- ✅ Better integration with systemd

## Integration with Other Roles

This role is typically applied early in host configuration:
1. **System role**: Configure basics (hostname, SSH)
2. **Users role**: Create users and deploy SSH keys
3. **Application roles**: Deploy services

## Common Issues

**"SSH connection lost after applying role":**
- Normal if you're connected on port 22 and it's removed from `ssh_ports`
- Reconnect using one of the new ports: `ssh -p 443 user@host`
- Always include at least one port in `ssh_ports`

**"Name or service not known" when connecting:**
- Check `/etc/hosts` on target has correct entry
- Verify DNS resolution if using external DNS
- May need to update your SSH config with correct hostname

**"Address already in use" errors:**
- Another service is using one of the SSH ports (e.g., actual HTTPS on 443)
- Check with: `sudo netstat -tlnp | grep <port>`
- Remove conflicting port from `ssh_ports`

**systemd socket doesn't start:**
- Check socket status: `systemctl status ssh.socket`
- View logs: `journalctl -u ssh.socket`
- Verify override file: `cat /etc/systemd/system/ssh.socket.d/override.conf`
- Test socket config: `systemd-analyze verify ssh.socket`

## Testing

```bash
# Check hostname
ansible all -l pve1 -m shell -a "hostname"
ansible all -l pve1 -m shell -a "hostname -f"

# Check /etc/hosts
ansible all -l pve1 -m shell -a "cat /etc/hosts | grep 127.0.1.1"

# Check SSH socket status
ansible all -l pve1 -m shell -a "systemctl status ssh.socket" --become

# Check listening ports
ansible all -l pve1 -m shell -a "ss -tlnp | grep ssh" --become

# Test SSH connection on alternate port
ssh -p 443 deploy@<host-ip>
```

## Security Considerations

### Multi-Port SSH
- **Use case**: Bypass restrictive firewalls that block port 22
- **Port 443**: Often allowed through corporate firewalls (HTTPS)
- **Custom ports**: Security through obscurity (minor benefit)
- **Trade-off**: More attack surface vs. accessibility

### Best Practices
- ✅ Use key-based authentication (configured elsewhere)
- ✅ Disable password authentication in sshd_config
- ✅ Consider fail2ban for brute force protection
- ✅ Use firewall rules to limit SSH access by source IP
- ❌ Don't rely solely on non-standard ports for security

## Advanced Configuration

### Using Standard Port Only

If you want traditional port 22 only:

```yaml
ssh_ports:
  - 22
```

### Firewall Bypass Setup

For hosts behind restrictive firewalls:

```yaml
ssh_ports:
  - 443      # HTTPS - usually allowed
  - 8443     # Alt HTTPS - sometimes allowed
  - 22       # Standard - may be blocked
```

### VPS Configuration

For public VPS, consider security:

```yaml
ssh_ports:
  - 5344     # Non-standard port reduces noise
```

Then use SSH config to remember:
```
# ~/.ssh/config
Host felix
    HostName 45.56.113.70
    Port 5344
    User deploy
```

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial setup
- [Users Role](../users/README.md) — User and SSH key management
- [Systemd Socket Activation](https://www.freedesktop.org/software/systemd/man/systemd.socket.html) — Official docs
