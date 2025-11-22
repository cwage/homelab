# Synology NFS Role

Manages NFS shares on Synology DS1815+ running DSM 7.1.1 via SSH/CLI commands.

## Prerequisites

1. SSH access to NAS with deploy user
2. Deploy user must have sudo access
3. Deploy SSH key placed in NAS authorized_keys

## Setup

The `deploy` user on portanas should be configured with:
- SSH public key from `ansible/keys/deploy.pub`
- Sudo access (passwordless recommended for automation)

### Creating the Deploy User

**IMPORTANT: `synogroup --member` replaces ALL group members, not just adds one!**

```bash
# Create user
sudo synouser --add deploy 'password' "Ansible Deploy User" 0 "" 0

# Add to administrators group (MUST include ALL members you want to keep!)
# This command REPLACES the entire group membership
sudo synogroup --member administrators cwage deploy

# Verify group membership
sudo synogroup --get administrators

# Set up SSH key
sudo mkdir -p /var/services/homes/deploy/.ssh
sudo cat /path/to/deploy.pub >> /var/services/homes/deploy/.ssh/authorized_keys
sudo chmod 700 /var/services/homes/deploy/.ssh
sudo chmod 600 /var/services/homes/deploy/.ssh/authorized_keys
sudo chown -R deploy:users /var/services/homes/deploy/.ssh

# Ensure deploy user has a login shell (DSM may set /sbin/nologin)
sudo usermod -s /bin/sh deploy
```

**Note:** If the deploy user suddenly can't log in via SSH, check that:
1. The shell is set to `/bin/sh` (not `/sbin/nologin`)
2. The user is still in the administrators group (DSM operations can reset this)

## Usage

### Discovery Mode

Run discovery to gather current NAS configuration:

```bash
make nas-discover
```

This will output:
- List of existing shares (via `synoshare --list`)
- NFS export rules (from `/etc/exports`)
- Local users and groups

Use this output to populate `inventories/host_vars/portanas.yml`.

### Check Mode (Dry Run)

Test playbook without making changes:

```bash
make nas-check
```

### Apply Configuration

Apply NFS share configuration:

```bash
make nas
```

## Configuration

Define NFS shares in `inventories/host_vars/portanas.yml`:

```yaml
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

## Synology CLI Commands Reference

- `synoshare --list` - List all shares
- `synoshare --add <name> <description> <path>` - Create share
- `synoshare --del <name>` - Delete share
- `synoservicecfg --list` - List services status
- `synoservicecfg --enable nfs` - Enable NFS service
- `synoservice --restart nfs` - Restart NFS service

## Implementation Status

- [x] Discovery mode (gather current state)
- [x] Inventory setup
- [ ] Share creation/modification
- [ ] NFS rule management
- [ ] Idempotency checks
- [ ] User/group management

## Future Enhancements

- Parse `/etc/exports` to check current state before modifying
- Support for SMB shares
- User quota management
- Snapshot/backup task management
