# Valheim Profile: vh-buttopia

This directory contains profile-specific files for the vh-buttopia server.

## Permission Files

Create these files to manage server access (one Steam ID or Xbox User ID per line):

- `adminlist.txt` - Admin privileges (can kick/ban, run commands)
- `permittedlist.txt` - Whitelist (if present, only these players can join)
- `bannedlist.txt` - Banned players

### Example adminlist.txt

```
# Steam ID format
76561198012345678
# Xbox User ID format
2535445291234567
```

## Getting Steam IDs

1. Open Steam profile in browser
2. URL ends with `/profiles/STEAMID64`
3. Or use https://steamid.io/

## Notes

- Server password is stored in OpenBao at `kv/services/gaming/vh-buttopia`
- World data is stored in `~/.config/unity3d/IronGate/Valheim/worlds_local/`
- LGSM config is at `~/lgsm/config-lgsm/vhserver/common.cfg`
