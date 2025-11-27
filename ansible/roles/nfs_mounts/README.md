## nfs_mounts role

Client-side helper for mounting NAS-provided NFS shares. The role installs the
appropriate NFS utilities, creates mount points, and manages `/etc/fstab`
entries with `ansible.posix.mount`.

### Variables

| Variable | Description | Default |
| --- | --- | --- |
| `nfs_mounts_enabled` | Toggle for the entire role | `true` |
| `nfs_mounts` | List of share definitions. Each item needs `src` and `path`. Optional keys: `name`, `opts`, `fstype`, `state`, `owner`, `group`, `mode`, `dump`, `passno`. | `[]` |
| `nfs_mounts_manage_packages` | Whether to install NFS client packages automatically | `true` |
| `nfs_mounts_package_map` | Map of `ansible_os_family` → package list | See defaults |
| `nfs_mounts_default_*` | Default attributes applied to each mount (state, fstype, opts, ownership, etc.) | See defaults |

### Example

```yaml
nfs_mounts:
  - name: backup
    src: portanas:/volume1/pve-backups
    path: /mnt/backup
    opts: "rw,_netdev,hard,intr,vers=3,noatime"
  - name: templates
    src: portanas:/volume1/pve-templates
    path: /mnt/pve-templates
    fstype: nfs
    opts: "rw,_netdev,vers=3"
```

Include the role in any host/VM/CT play after base packages/users so mounts come
up with the correct permissions.
