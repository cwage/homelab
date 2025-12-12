# OpenBao Secrets Organization

This document describes the secret organization structure and access patterns for the homelab OpenBao instance.

## KV Structure

All secrets are stored in the `kv` secrets engine (KV v2) with the following hierarchy:

```
kv/
├── infra/                    # Infrastructure/provisioning secrets
│   ├── proxmox/              # Proxmox API tokens
│   ├── cloudflare/           # DNS/Let's Encrypt API tokens
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

## Token Management

### Creating the ansible-deploy Token

```bash
ssh bao.lan.quietlife.net

export BAO_ADDR="https://127.0.0.1:8200"
export BAO_SKIP_VERIFY=true
export BAO_TOKEN="<root-token>"

# Create the policy
bao policy write ansible-deploy - <<'EOF'
path "kv/data/infra/*" {
  capabilities = ["read"]
}
path "kv/data/backup/*" {
  capabilities = ["read"]
}
path "kv/data/services/*" {
  capabilities = ["read"]
}
EOF

# Create token (30-day TTL)
bao token create -policy=ansible-deploy -ttl=720h -display-name="ansible-deploy"
```

### Token Rotation

Tokens are created with a 30-day TTL. To rotate:

1. Create a new token with the same policy
2. Update `BAO_TOKEN` in `/.env`
3. Test with `make ansible-openbao-test`
4. Revoke the old token (optional but recommended)

```bash
# Revoke old token
bao token revoke <old-token>
```

## Storing Secrets

Use the `bao kv put` command to store secrets:

```bash
# Store a secret
bao kv put kv/infra/proxmox api_token_id="user@pve!token" api_token_secret="xxx"

# Read it back
bao kv get kv/infra/proxmox
```

Note: KV v2 paths use `kv/data/` for the API but `kv/` for the CLI.

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
