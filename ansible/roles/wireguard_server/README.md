# WireGuard Server Role

Ansible role for configuring WireGuard VPN server on OpenBSD firewalls.

## Overview

This role configures an OpenBSD host as a WireGuard VPN hub, allowing road warrior clients to connect and access the local network. It handles:

- Installation of `wireguard-tools` package (provides `wg` command for management)
- WireGuard interface configuration (`hostname.wg0`)
- IP forwarding enablement
- Integration with the `openbsd_firewall` role for packet filter rules

## Requirements

- OpenBSD 7.1+ (native `wg(4)` kernel driver support)
- Private key must be manually generated and placed before deployment
- Must be used in conjunction with `openbsd_firewall` role
- Docker and docker-compose (all ansible operations run via `make` commands in Docker)

## Role Variables

### Required Variables

Configure these in `host_vars/<hostname>.yml`:

```yaml
wireguard_peers:
  - name: client1
    public_key: "BASE64_PUBLIC_KEY"
    allowed_ips: "10.10.16.2/32"
    persistent_keepalive: 0
```

### Optional Variables (with defaults)

See `defaults/main.yml` for full list:

```yaml
wireguard_interface: wg0
wireguard_port: 51923
wireguard_vpn_network: 10.10.16.0/24
wireguard_vpn_ip: 10.10.16.1
wireguard_vpn_netmask: 255.255.255.0
wireguard_private_key_path: /etc/wireguard/private.key
wireguard_lan_interface: em1
wireguard_lan_network: 10.10.15.0/24
wireguard_enable_ip_forwarding: true
```

## Setup Instructions

### 1. Generate Private Key on Target Host

Generate a private key on the firewall. You can either SSH directly or use make adhoc:

**Option A: SSH directly (recommended for security)**
```bash
ssh fw1
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard
openssl rand -base64 32 > /etc/wireguard/private.key
chmod 600 /etc/wireguard/private.key
```

**Option B: Via make adhoc**
```bash
make adhoc HOSTS=fw1 MODULE=raw ARGS='mkdir -p /etc/wireguard && chmod 700 /etc/wireguard && openssl rand -base64 32 > /etc/wireguard/private.key && chmod 600 /etc/wireguard/private.key'
```

Store this private key securely in your password manager (e.g., Bitwarden).

### 2. Derive Public Key

You need to derive the public key from the private key. The ansible role installs `wireguard-tools`, which provides the `wg` command:

**After running the ansible playbook:**

```bash
# Derive public key (wireguard-tools will be installed by ansible)
cat /etc/wireguard/private.key | wg pubkey
```

**Before running ansible (alternative methods):**

If you need the public key before deploying, you can:

**Option A: Use a Linux system with WireGuard tools**

```bash
# On any Linux system with wireguard-tools installed
echo "PASTE_PRIVATE_KEY_HERE" | wg pubkey
```

**Option B: Use Python with cryptography library**

```bash
python3 << 'EOF'
import base64
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

# Read the private key
with open('/etc/wireguard/private.key', 'r') as f:
    private_key_b64 = f.read().strip()

# Decode and create key object
private_bytes = base64.b64decode(private_key_b64)
private_key = X25519PrivateKey.from_private_bytes(private_bytes)

# Derive public key
public_key = private_key.public_key()
public_key_b64 = base64.b64encode(public_key.public_bytes_raw()).decode('ascii')

print(f"Public key: {public_key_b64}")
EOF
```

The public key will be used by clients to connect to the server.

### 3. Generate Client Keys

Each client needs its own key pair. For example:

**Linux/Android clients:**
```bash
wg genkey | tee private.key | wg pubkey > public.key
```

**Android WireGuard app:**
- Use the built-in key generator
- Export the public key from the app

### 4. Configure Ansible Variables

Create or update `inventories/host_vars/fw1.yml`:

```yaml
---
wireguard_peers:
  - name: laptop
    public_key: "CLIENT_PUBLIC_KEY_HERE"
    allowed_ips: "10.10.16.2/32"
    persistent_keepalive: 0

  - name: phone
    public_key: "CLIENT_PUBLIC_KEY_HERE"
    allowed_ips: "10.10.16.3/32"
    persistent_keepalive: 0
```

### 5. Run the Playbook

```bash
make firewall
```

This will run both the `wireguard_server` and `openbsd_firewall` roles via Docker, which:
1. Installs wireguard-tools package
2. Checks that the private key exists
3. Deploys `hostname.wg0` configuration
4. Enables IP forwarding
5. Brings up the WireGuard interface
6. Updates `pf.conf` with WireGuard rules
7. Reloads the packet filter

## Integration with openbsd_firewall Role

This role is designed to work with the `openbsd_firewall` role. The firewall role's `pf.conf.j2` template conditionally includes WireGuard rules when `wireguard_interface` is defined.

The WireGuard rules added to pf.conf:
- Allow incoming UDP traffic on WireGuard port
- Allow traffic between VPN network and LAN
- Allow peer-to-peer traffic within VPN (optional)

## Client Configuration

### Example Client Config (portaptty laptop)

```ini
[Interface]
PrivateKey = <client-private-key>
Address = 10.10.16.2/32
DNS = 10.10.16.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <firewall-public-ip>:51923
AllowedIPs = 10.10.15.0/24, 10.10.16.0/24
```

Save this as a `.conf` file and use with `wg-quick`:
```bash
# On Linux
sudo wg-quick up /etc/wireguard/wg0.conf
```

### Example Client Config (android phone)

Same as laptop config above, but with `Address = 10.10.16.3/32`

### Android QR Code Setup

The Android WireGuard app can scan QR codes for easy configuration. Here's how to generate one:

**Prerequisites:**
- Server public key (derived from fw1's private key)
- Client private key (generated in Android app)
- Firewall's public IP address

**Generate QR Code:**

On your laptop or control machine with `qrencode` installed:

```bash
# Install qrencode if needed
sudo apt install qrencode  # Debian/Ubuntu
brew install qrencode      # macOS

# Create client config file
cat > android-wg.conf << 'EOF'
[Interface]
PrivateKey = CLIENT_PRIVATE_KEY_HERE
Address = 10.10.16.3/32

[Peer]
PublicKey = SERVER_PUBLIC_KEY_HERE
Endpoint = YOUR_FIREWALL_PUBLIC_IP:51923
AllowedIPs = 10.10.15.0/24, 10.10.16.0/24
EOF

# Generate QR code - display in terminal
qrencode -t ansiutf8 < android-wg.conf

# Or save as PNG image
qrencode -o android-wg.png < android-wg.conf
```

**Import to Android:**
1. Open WireGuard app
2. Tap "+" to add tunnel
3. Select "Scan from QR code"
4. Scan the QR code from your terminal or image

**Security Note:** The QR code contains the client's private key, so don't share it publicly or leave it displayed. Delete the config file after scanning.

**Alternative (Manual Entry):**
You can also manually enter the configuration in the Android app instead of using a QR code.

## Testing

After deployment:

```bash
# On the firewall, verify interface is up
ifconfig wg0

# Check WireGuard status and connected peers
wg show

# Check WireGuard is listening
netstat -an | grep 51923

# Check IP forwarding is enabled
sysctl net.inet.ip.forwarding

# From a client, test connectivity
ping 10.10.16.1         # Ping firewall VPN IP
ping 10.10.15.1         # Ping firewall LAN IP
ping 10.10.15.x         # Ping other LAN hosts
```

### Monitoring Connected Peers

The `wg show` command (from wireguard-tools) provides valuable information:

```bash
# Show all WireGuard interfaces and peers
wg show

# Example output:
# interface: wg0
#   public key: <server-public-key>
#   private key: (hidden)
#   listening port: 51923
#
# peer: <client-public-key>
#   allowed ips: 10.10.16.2/32
#   latest handshake: 45 seconds ago
#   transfer: 12.45 KiB received, 8.23 KiB sent
```

This shows:
- Which peers are configured
- When they last connected (latest handshake)
- How much data has been transferred
- Whether they're actively connected (recent handshake = connected)

## Security Notes

### Private Key Management

- **NEVER** commit private keys to the repository
- **ALWAYS** generate keys on the target host
- Store private keys in a secure password manager (Bitwarden, OpenBao, etc.)
- Only public keys should be in ansible variables

### Future: OpenBao Integration

This setup is designed to eventually integrate with OpenBao for centralized secrets management:
- Private keys will be stored in OpenBao
- Ansible will fetch keys from OpenBao during deployment
- Enables automated key rotation

### Firewall Rules

The role creates restrictive firewall rules:
- Only allows WireGuard on the configured port
- Peer AllowedIPs are strictly enforced
- Split-tunnel only - clients route only homelab traffic through VPN

## Troubleshooting

### Interface not coming up

```bash
# Check for errors
sh -x /etc/netstart wg0

# Verify private key exists and is readable
ls -la /etc/wireguard/private.key

# Check hostname.wg0 syntax
cat /etc/hostname.wg0
```

### Clients can't connect

```bash
# Check firewall is allowing UDP traffic
tcpdump -i egress udp port 51923

# Verify pf rules
pfctl -sr | grep wg

# Check WireGuard interface status
ifconfig wg0
```

### Can reach VPN IP but not LAN

```bash
# Verify IP forwarding is enabled
sysctl net.inet.ip.forwarding

# Check pf rules allow forwarding
pfctl -sr | grep wg_net
```

## References

- [OpenBSD wg(4) Manual](https://man.openbsd.org/wg)
- [OpenBSD hostname.if(5) Manual](https://man.openbsd.org/hostname.if)
- [WireGuard Protocol](https://www.wireguard.com/)
- [Project VPN Documentation](../../docs/VPN.md)
