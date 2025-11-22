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
- List of existing shares (via `synoshare --enum ALL`)
- NFS export rules (from `/etc/exports`)
- Local users and groups

Use this output to populate `inventories/host_vars/portanas.yml`.

**Note:** `synoshare --enum ALL` is used instead of `--list` as it provides more detailed output. This command is not documented in the official Synology CLI guide but is present in DSM 7.

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

### Share Management
- `synoshare --enum ALL` - List all shares with details (undocumented DSM 7 command)
- `synoshare --get <name>` - Get share details
- `synoshare --add <name> <description> <path> "" "" "" 1 0` - Create share
- `synoshare --del TRUE <name>` - Delete share and its data
- `synoshare --del FALSE <name>` - Delete share configuration only

### NFS Service Management (DSM 7)
- `systemctl status nfs-server` - Check NFS service status
- `systemctl is-active nfs-server` - Check if NFS is running
- `systemctl enable --now nfs-server` - Enable and start NFS service
- `systemctl restart nfs-server` - Restart NFS service
- `exportfs -ra` - Reload NFS exports from /etc/exports

**Note:** DSM 7 uses `systemctl` for service management. Old DSM 6 commands (`synoservicecfg`, `synoservice`) do not exist in DSM 7.

## Implementation Details

### Share Creation
Uses `synoshare --add` to create shares with:
- Share name, description, and path
- Empty access control lists (managed separately if needed)
- Browsable in network (visible)
- No advanced restrictions

### NFS Export Management
Manages a dedicated Ansible-controlled block in `/etc/exports`:
- Clearly marked with `BEGIN/END ANSIBLE MANAGED BLOCK` comments
- Uses `sed` to remove old block and append new one
- Reloads exports with `exportfs -ra` after changes
- **Trade-off**: Manual DSM GUI changes to these shares may be overwritten

### Idempotency
- Checks if share exists before creating (`synoshare --get`)
- Only creates missing shares
- Always updates `/etc/exports` block (intentional - ensures consistency)

## Implementation Status

- [x] Discovery mode (gather current state)
- [x] Inventory setup
- [x] Share creation via synoshare
- [x] NFS export management via /etc/exports
- [x] Idempotency checks for share creation
- [x] NFS service enable/restart
- [ ] User/group management

## Important Notes

**Managing NFS Exports:**
- Ansible manages exports in a dedicated block in `/etc/exports`
- Do NOT configure these specific shares via DSM web GUI, or changes will be lost
- If DSM overwrites the file, simply re-run `make nas` to restore

**Synology-Specific Behavior:**
- DSM may regenerate `/etc/exports` during updates or service restarts
- Our block will persist through normal operations but may need re-applying after DSM updates
- The `synoshare` command creates shares that DSM recognizes and manages

## Future Enhancements

- Support for SMB shares
- User quota management
- Snapshot/backup task management
- More sophisticated /etc/exports parsing to detect conflicts
