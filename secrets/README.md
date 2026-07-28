# sops-encrypted secrets

Age-encrypted secrets for NixOS hosts that **cannot reach OpenBao**.

OpenBao remains the source of truth for everything on the LAN. The
`openbao-agent` module authenticates with an AppRole CIDR-bound to a static LAN
address and talks to `bao.lan.quietlife.net:8200` — neither of which works from
a public VPS. Rather than exposing OpenBao to the internet, off-LAN hosts get
their secrets committed here, encrypted.

Files in this directory are safe to commit: the values are age-encrypted and
only the listed recipients in `../.sops.yaml` can decrypt them. The keys and
comments stay in plaintext, which is why the field names below are descriptive
but the values are not.

## Current files

| File | Host | Contents |
|---|---|---|
| `xmpp1.yaml` | xmpp1 | `cwage-password-hash`, `coturn-auth-secret`, `acme-cloudflare-env` |

## Editing

```bash
nix run nixpkgs#sops -- secrets/xmpp1.yaml
```

sops decrypts into `$EDITOR`, then re-encrypts on save. Never `cat` a decrypted
secret into a terminal you don't control.

## Expected shape of xmpp1.yaml

```yaml
cwage-password-hash: "$y$j9T$..."        # same value as kv/infra/users/cwage
coturn-auth-secret: "<hex string>"        # same value as kv/infra/coturn/auth
acme-cloudflare-env: |
  CF_DNS_API_TOKEN=<zone-scoped cloudflare token>
```

`acme-cloudflare-env` is consumed as a systemd `EnvironmentFile`, so it must be
`KEY=value` lines, not a bare token.

## Relationship to OpenBao

`coturn-auth-secret` and `cwage-password-hash` are duplicated from OpenBao
(`kv/infra/coturn/auth`, `kv/infra/users/cwage`). That duplication is
deliberate — OpenBao stays canonical, and this is a copy for a host that cannot
reach it. If you rotate either value in OpenBao, rotate it here too.
