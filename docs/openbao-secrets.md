# OpenBao Secrets Organization

This document describes the secret organization structure and access patterns for the homelab OpenBao instance.

## KV Structure

All secrets are stored in the `kv` secrets engine (KV v2) with the following hierarchy:

```
kv/
├── infra/                    # Infrastructure/provisioning secrets
│   ├── proxmox/              # Proxmox API tokens
│   │   └── api_token_id, api_token_secret
│   ├── cloudflare/           # Cloudflare API tokens
│   │   ├── api_token, zone_id           # lego ACME client (cert renewal)
│   │   ├── tunnel/
│   │   │   └── token                    # cloudflared container (tunnel runtime)
│   │   └── tofu/
│   │       └── api_token, account_id    # OpenTofu Cloudflare provider (DNS + tunnel mgmt)
│   ├── certs/                # TLS certificates (Let's Encrypt)
│   │   └── lan.quietlife.net # Wildcard cert for *.lan.quietlife.net
│   ├── linkding/             # Linkding bookmark manager
│   │   └── superuser/
│   │       └── name, password             # Admin account credentials
│   └── ssh/                  # SSH keys (if stored here)
│
├── services/                 # Application/service secrets
│   ├── postgres/             # Database credentials
│   ├── redis/
│   ├── traefik/              # Reverse proxy certs/config
│   └── <app-name>/           # Per-app secrets
│
├── backup/                   # Backup-related credentials
│   └── openbao/              # OpenBao backup token
│
└── users/                    # User credentials (if needed)
```

## Access Policies

### ansible-deploy

Used by Ansible and OpenTofu for infrastructure automation. Has read-only access to secrets needed during provisioning and configuration.

```hcl
# Read infrastructure secrets (API tokens, etc.)
path "kv/data/infra/*" {
  capabilities = ["read"]
}

# Read backup credentials
path "kv/data/backup/*" {
  capabilities = ["read"]
}

# Read service secrets for deployment
path "kv/data/services/*" {
  capabilities = ["read"]
}
```

### Future: Service-Specific Policies

For containers/services that need direct OpenBao access, create narrow policies:

```hcl
# Example: postgres-backup policy
path "kv/data/services/postgres/*" {
  capabilities = ["read"]
}
```

## Workstation Bootstrap

To set up a new workstation (or replace an expired token), you just need to generate a
token against the existing `ansible-deploy` policy and drop it into your `.env`.

1. SSH into the OpenBao server and authenticate with the root token:

```bash
ssh bao.lan.quietlife.net
export BAO_ADDR="https://bao.lan.quietlife.net:8200"
bao login
# Enter root token from Bitwarden
```

2. Create a token:

```bash
bao token create -policy=ansible-deploy -ttl=720h -display-name="ansible-deploy-<machine>"
```

3. Copy the token into your repo's `.env`:

```
BAO_TOKEN=<token>
```

4. Test connectivity:

```bash
make ansible-openbao-test
```

Old tokens expire after 30 days — no cleanup needed, but you can revoke them
explicitly with `bao token revoke <old-token>` if you prefer.

### Initial Policy Setup (One-Time)

The `ansible-deploy` policy only needs to be created once on the server. If it
doesn't exist yet (fresh OpenBao deployment), see the
[Ansible Deploy Token Setup](openbao.md#ansible-deploy-token-setup) section in
`openbao.md`.

## Storing Secrets

Use the `bao kv put` command to store secrets:

```bash
# Store a secret
bao kv put kv/infra/proxmox api_token_id="user@pve!token" api_token_secret="xxx"

# Read it back
bao kv get kv/infra/proxmox
```

Note: KV v2 paths use `kv/data/` for the API but `kv/` for the CLI.

### Cloudflare API Token (for Let's Encrypt)

The Cloudflare API token is retrieved by Makefile targets and passed to the `lego` container for DNS-01 ACME challenges to obtain wildcard certificates for `*.lan.quietlife.net`.

1. Create a token at https://dash.cloudflare.com/profile/api-tokens
2. Required permissions: **Zone:DNS:Edit** and **Zone:Zone:Read** for the `quietlife.net` zone
3. Get your zone ID from the Cloudflare dashboard (Overview page, right sidebar)
4. Store in OpenBao:

```bash
bao kv put kv/infra/cloudflare api_token="your-cloudflare-api-token" zone_id="your-zone-id"
```

The `make lego-renew` command will automatically retrieve these values from OpenBao.

## Retrieving Secrets in Ansible

Use the `community.hashi_vault.vault_kv2_get` lookup plugin:

```yaml
# Store secret in a variable (recommended - avoids logging)
- name: Retrieve Proxmox API token
  set_fact:
    proxmox_secret: "{{ lookup('community.hashi_vault.vault_kv2_get',
                        'infra/proxmox',
                        engine_mount_point='kv',
                        url=openbao_addr,
                        token=openbao_token,
                        validate_certs=openbao_validate_certs).secret }}"

# Use the secret (mask in any debug output)
- name: Verify secret retrieved (masked)
  debug:
    msg: "Retrieved API token: {{ proxmox_secret.api_token_secret[:4] }}****"
```

The lookup returns an object with a `.secret` attribute containing the secret data as a dict.

**Important**: Never log full secret values. Use `set_fact` to store secrets in variables, and mask/truncate when debugging.

The `openbao_addr`, `openbao_token`, and `openbao_validate_certs` variables are defined in `ansible/inventories/group_vars/all.yml` and populated from environment variables (`BAO_ADDR`, `BAO_TOKEN`, `BAO_SKIP_VERIFY`).

## Related

- [Issue #67](https://github.com/cwage/homelab/issues/67) - Trusted orchestrator pattern implementation
- `ansible/playbooks/openbao-test.yml` - Test playbook for OpenBao connectivity
