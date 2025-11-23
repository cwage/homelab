# Users Role

Manages local user accounts on Linux systems, including user creation, sudo configuration, and SSH key deployment.

## Purpose

This role provides centralized user management for all managed Linux hosts. It creates users, configures their shells and groups, sets up passwordless sudo where needed, and deploys SSH public keys for authentication.

## Requirements

- **Target OS**: Debian/Ubuntu Linux (uses `adduser.conf`)
- **Privileges**: Requires `become: true` (sudo/root access)
- **Packages**: Installs `sudo` if not present
- **Python**: Python 3 on target hosts (standard Ansible requirement)

## Role Variables

### Required Variables

None — the role will do nothing if `managed_users` is empty or undefined.

### Optional Variables (with defaults)

Defined in `defaults/main.yml`:

```yaml
# List of users to manage
managed_users: []
```

### User Object Structure

Each item in `managed_users` supports these keys:

```yaml
managed_users:
  - name: username              # Required: username
    shell: /bin/bash            # Optional: shell (default: /bin/bash)
    groups: ["sudo", "docker"]  # Optional: additional groups (default: [])
    sudo_nopasswd: true         # Optional: passwordless sudo (default: false)
    ssh_pubkey: "ssh-ed25519 AAAA..."  # Optional: inline SSH public key
    ssh_pubkey_file: "keys/user.pub"   # Optional: path to public key file (relative to repo root)
```

**Key Notes:**
- `name` is required for each user
- `shell` defaults to `/bin/bash` if not specified
- `groups` are appended to the user's groups (primary group is preserved)
- `sudo_nopasswd` adds the user to sudoers with NOPASSWD
- Either `ssh_pubkey` or `ssh_pubkey_file` can be used (file takes precedence)
- Public key files are relative to the repository root (e.g., `ansible/keys/deploy.pub`)

## Dependencies

None. This is a standalone role.

## Example Usage

### Basic Playbook

```yaml
---
- name: Manage users on Proxmox
  hosts: proxmox
  become: true
  roles:
    - users
```

### Example Inventory Configuration

In `inventories/group_vars/proxmox.yml`:

```yaml
---
managed_users:
  - name: deploy
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/deploy.pub"

  - name: cwage
    shell: /bin/bash
    groups: ["sudo", "docker"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/cwage.pub"

  - name: backup
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: false
    ssh_pubkey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... backup@example.com"
```

### Host-Specific Users

In `inventories/host_vars/pve1.yml`:

```yaml
---
managed_users:
  - name: deploy
    shell: /bin/bash
    groups: ["sudo"]
    sudo_nopasswd: true
    ssh_pubkey_file: "keys/deploy.pub"
```

### Running the Role

```bash
# Preview changes (dry-run)
make users-check

# Apply changes
make users
```

Or with ansible-playbook directly:
```bash
ansible-playbook playbooks/users.yml --check --diff  # Preview
ansible-playbook playbooks/users.yml                 # Apply
```

## What This Role Does

### 1. Install Prerequisites
- Ensures `sudo` package is installed
- Creates `sudo` group if it doesn't exist (Debian/Ubuntu)

### 2. Configure Home Directory Permissions
- Sets default home directory mode to `0700` in `/etc/adduser.conf`
- Applies to newly created users (not existing users)
- Fails gracefully on non-Debian systems

### 3. Create/Manage Users
- Creates users with specified shell and groups
- Sets home directory and creates if missing
- Appends groups (doesn't replace existing groups)
- Idempotent: safe to run multiple times

### 4. Deploy SSH Public Keys
- Reads public key from file or inline variable
- Creates `.ssh/authorized_keys` with correct permissions
- Sets permissions: `.ssh/` is 0700, `authorized_keys` is 0600
- Overwrites existing keys (exclusive management)

### 5. Configure Sudo Access
- Creates sudoers drop-in file for users with `sudo_nopasswd: true`
- File location: `/etc/sudoers.d/<username>`
- Validates sudoers syntax before writing
- Enables passwordless sudo for automated deployments

## Outputs

After running this role:
- Users exist with specified configuration
- Users can log in via SSH using deployed keys
- Users with `sudo_nopasswd: true` can run `sudo` without password
- Home directories are created with mode 0700

## Assumptions and Limitations

### Assumptions
- Target systems are Debian or Ubuntu (adduser.conf management)
- The `sudo` group provides sudo privileges
- SSH public keys are already generated (role doesn't generate keys)

### Limitations
- Does not remove users (only creates/updates)
- Does not manage user passwords (SSH key auth only)
- Does not handle user removal from groups
- `/etc/adduser.conf` modification assumes Debian-family systems

### Security Considerations
- Private SSH keys should never be managed by this role
- Public keys are safe to store in inventory or files
- Passwordless sudo is convenient but should be limited to trusted users
- Consider using `sudo_nopasswd: false` for interactive users

## Integration with Other Roles

This role is typically applied before other roles that require specific users:
1. **Deploy user creation**: Run `users` role first
2. **Application deployment**: Assumes deploy user exists
3. **Service management**: User-specific services depend on user existence

## Common Issues

**"User not found" after role runs:**
- Check playbook has `become: true`
- Verify inventory defines `managed_users`
- Run with `-vv` to see which users are processed

**"Permission denied" when using deployed keys:**
- Verify public key matches private key: `ssh-keygen -y -f private.key`
- Check `.ssh` directory permissions on target: should be 0700
- Check `authorized_keys` permissions: should be 0600
- Ensure SELinux context is correct (if applicable)

**Sudo not working after passwordless configuration:**
- Verify sudoers file syntax: `sudo visudo -c`
- Check file permissions in `/etc/sudoers.d/`: should be 0440
- Ensure user is in `sudo` group: `groups <username>`

## Testing

```bash
# Test with check mode (no changes)
ansible-playbook playbooks/users.yml --check

# Apply with verbose output
ansible-playbook playbooks/users.yml -vv

# Verify user exists
ansible all -l pve1 -m shell -a "id deploy"

# Verify sudo access
ansible all -l pve1 -m shell -a "sudo whoami" --become

# Verify SSH key
ansible all -l pve1 -m shell -a "cat /home/deploy/.ssh/authorized_keys"
```

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial SSH setup
- [System Role](../system/README.md) — Basic system configuration
- [Ansible Documentation](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/user_module.html) — User module reference
