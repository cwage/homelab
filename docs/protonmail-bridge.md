# ProtonMail Bridge Mail Relay

The `mail` VM (10.10.15.14) runs ProtonMail Bridge to provide SMTP relay for the homelab. This enables alerting, monitoring, and other services to send email through your ProtonMail account.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    mail VM (10.10.15.14)                        │
│                                                                 │
│  ┌─────────────┐    ┌──────────────────┐    ┌───────────────┐  │
│  │ socat:587   │───▶│ protonmail-bridge │◀───│   pass/GPG    │  │
│  │  (STARTTLS) │    │   (localhost)     │    │  (encrypted)  │  │
│  └─────────────┘    └──────────────────┘    └───────────────┘  │
│         │                    │                      │          │
│         │                    │                      │          │
└─────────┼────────────────────┼──────────────────────┼──────────┘
          │                    │                      │
          ▼                    ▼                      ▼
    LAN clients          Proton servers          OpenBao
      (SMTP)             (encrypted)         (GPG passphrase)
```

## Security Model

- GPG key protects the `pass` password store containing bridge credentials
- GPG key passphrase is stored in OpenBao, not on disk
- Service startup fetches passphrase from OpenBao and presets it in gpg-agent
- Compromise of the mail VM alone is insufficient - attacker also needs OpenBao access

## Bootstrap Process

After running `make ansible-mail`, complete these manual steps:

### 1. Generate and store GPG passphrase in OpenBao

From your workstation with `bao` CLI configured:

```bash
# Generate a secure passphrase using OpenBao
PASSPHRASE=$(bao write -f -field=random_bytes sys/tools/random/32 format=base64)

# Store it
bao kv put kv/infra/mail/gpg-passphrase passphrase="$PASSPHRASE"

# Verify
bao kv get kv/infra/mail/gpg-passphrase

# Save the passphrase temporarily - you'll need it in step 3
echo "$PASSPHRASE"
```

### 2. Create OpenBao policy and token for the mail service

The protonmail service needs a token to fetch the GPG passphrase from OpenBao on startup.

#### 2a. Create a policy (from your workstation with admin access to OpenBao)

```bash
# Create the policy file
cat > /tmp/protonmail-bridge-policy.hcl << 'EOF'
# Allow reading the GPG passphrase for protonmail-bridge
path "kv/data/infra/mail/gpg-passphrase" {
  capabilities = ["read"]
}
EOF

# Upload the policy to OpenBao
bao policy write protonmail-bridge /tmp/protonmail-bridge-policy.hcl

# Clean up
rm /tmp/protonmail-bridge-policy.hcl
```

#### 2b. Create a token with that policy

```bash
# Create a long-lived token for the service
# -period=768h means it will auto-renew if used within 32 days
bao token create \
  -policy=protonmail-bridge \
  -display-name="protonmail-bridge-mail-vm" \
  -period=768h
```

Copy the `token` value from the output - you'll need it in step 4.

### 3. SSH to mail server and deploy the token

```bash
ssh mail.lan.quietlife.net

# Create the token file (with export so child processes inherit it)
echo "export BAO_TOKEN=<token-from-2b>" | sudo tee /home/protonmail/.bao_token > /dev/null
sudo chown protonmail:protonmail /home/protonmail/.bao_token
sudo chmod 600 /home/protonmail/.bao_token

# Now become the protonmail user (stay as this user for remaining steps)
sudo -u protonmail -i
```

### 4. Generate GPG key with the passphrase

```bash
# Replace YOUR_PASSPHRASE with the value from step 1
sed "s/REPLACE_WITH_PASSPHRASE/YOUR_PASSPHRASE/" ~/.gpgparams > /tmp/gpgparams
gpg --generate-key --batch /tmp/gpgparams
shred -u /tmp/gpgparams
```

### 5. Initialize pass

```bash
pass init "ProtonMail Bridge"
```

### 6. Test the startup script

```bash
source ~/.bao_token
~/bin/protonmail-bridge-start.sh
# Should see "Starting ProtonMail Bridge..." - Ctrl+C to stop
```

### 7. Login to ProtonMail Bridge

```bash
protonmail-bridge --cli
```

In the CLI:
```
>>> login
# Enter your ProtonMail credentials and 2FA if prompted

>>> info
# Note the Username and Password shown - these are the SMTP credentials

>>> exit
```

### 8. Store bridge credentials in OpenBao

From your workstation:

```bash
bao kv put kv/infra/mail/bridge-credentials \
  username="<username from info>" \
  password="<password from info>"
```

### 9. Enable and start services

```bash
sudo systemctl enable --now protonmail-bridge socat-smtp
```

## Verification

Test SMTP connectivity from another host:

```bash
# Simple connection test
nc -zv mail.lan.quietlife.net 587

# Or with openssl for STARTTLS
openssl s_client -connect mail.lan.quietlife.net:587 -starttls smtp
```

## Service Management

```bash
# Check status
systemctl status protonmail-bridge socat-smtp

# View logs
journalctl -u protonmail-bridge -f

# Restart (will re-fetch passphrase from OpenBao)
sudo systemctl restart protonmail-bridge
```

## Troubleshooting

### Bridge won't start - "Failed to fetch passphrase"
- Check BAO_TOKEN is valid: `curl -H "X-Vault-Token: $BAO_TOKEN" https://bao.lan.quietlife.net:8200/v1/kv/data/infra/mail/gpg-passphrase`
- Verify the secret exists in OpenBao

### Bridge won't start - "Could not find GPG keygrip"
- GPG key wasn't generated properly
- Re-run step 3 to generate the key

### "Connection refused" from clients
- Check socat service is running: `systemctl status socat-smtp`
- Check bridge is running: `systemctl status protonmail-bridge`

### Need to re-authenticate with ProtonMail
- Stop the service: `sudo systemctl stop protonmail-bridge`
- Login interactively: `sudo -u protonmail protonmail-bridge --cli`
- Re-login and get new credentials
- Update credentials in OpenBao if they changed
- Restart: `sudo systemctl start protonmail-bridge`
