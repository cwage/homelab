# Gaming servers

Game servers run on a Linode VPS (`gaming1`). Each game profile gets its own Linux user with an isolated [LinuxGSM](https://linuxgsm.com/) installation. Ansible provisions the users and dependencies; LGSM handles the actual game server lifecycle.

## Quick reference

| Command | Description |
|---------|-------------|
| `make ansible-gaming` | Full provision (all active profiles) |
| `make ansible-gaming PROFILE=name` | Full provision (single profile) |
| `make ansible-gaming-check` | Dry-run with --check/--diff |
| `make ansible-gaming-configs` | Deploy configs/mods only |
| `make ansible-gaming-archive PROFILE=name` | Archive and purge a profile |

## New profile setup

1. Add profile to `ansible/inventories/group_vars/gaming_servers.yml`
2. Run `make ansible-gaming PROFILE=<name>` to provision user and dependencies
3. Install the game server (see game-specific instructions below)
4. Start the server and verify it works
5. (Optional) Add configs/mods to `ansible/roles/gaming_server/files/profiles/<name>/`
6. Deploy configs with `make ansible-gaming-configs PROFILE=<name>`

## Game-specific setup

**Vintage Story / Valheim (LinuxGSM)**

After provisioning, install the game via LGSM:
```bash
ssh gaming.quietlife.net
sudo -iu <profile>
./<script> install    # e.g., ./vintsserver install, ./vhserver install
./<script> start
```

## Day-to-day operations

Ansible never auto-restarts game servers. After config changes, manually restart:
```bash
ssh gaming.quietlife.net
sudo -iu <profile>
./<script> restart
```

## Archiving profiles

To safely remove a profile and reclaim disk space:

1. Set `active: false` in `ansible/inventories/group_vars/gaming_servers.yml`
2. Stop the server: `sudo -iu <profile> ./<script> stop`
3. Preview: `make ansible-gaming-archive PROFILE=<name>`
4. Execute: `make ansible-gaming-archive PROFILE=<name> CONFIRM=yes`
5. Copy the tarball: `scp gaming.quietlife.net:/tmp/<name>-*.tar.gz ./`

To restore later:
1. Set `active: true` in group_vars
2. Run `make ansible-gaming PROFILE=<name>`
3. Extract the tarball to restore world data
