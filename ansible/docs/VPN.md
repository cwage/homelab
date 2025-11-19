# WireGuard VPN Setup

## Overview

This document outlines the WireGuard VPN architecture for providing secure remote access to the homelab network (10.10.15.0/24).

**Key Facts:**
- WireGuard uses UDP only (not TCP)
- Modern, secure VPN protocol with minimal attack surface
- Native kernel support in OpenBSD 7.1+ via `wg(4)` driver
- Simple configuration with public key cryptography (no PKI/certificates)

## Network Topology

```
                            Internet
                                |
                    +-----------+-----------+
                    |                       |
            [Laptop: portaptty]     [Android Phone]
            (Road Warrior)          (Road Warrior)
            wg0: 10.10.16.2/32     wg0: 10.10.16.3/32
                    |                       |
                    +-----------+-----------+
                                |
                    [Firewall: jlo] (Hub)
                    em0: 10.10.15.1/24 (LAN)
                    wg0: 10.10.16.1/24 (VPN)
                                |
                        10.10.15.0/24 Network
                        (Homelab LAN)
```

## Architecture: Hub-and-Spoke

**Hub:** jlo (OpenBSD firewall at 10.10.15.1)
- Acts as WireGuard server/router
- Routes traffic between VPN peers and LAN (no NAT needed - jlo is already the gateway)
- Always available (unless the network is down)

**Spokes:**
- **portaptty** (laptop): Intermittent connection, managed separately via different ansible repo
- **android phone**: Intermittent connection, configured via WireGuard Android app

## IP Addressing Scheme

### WireGuard Network: 10.10.16.0/24

| Host | WireGuard IP | Role | Managed By |
|------|-------------|------|------------|
| jlo | 10.10.16.1/24 | Hub/Gateway | This repo |
| portaptty | 10.10.16.2/32 | Road Warrior | Separate ansible repo |
| android | 10.10.16.3/32 | Road Warrior | WireGuard Android app (manual) |

### LAN Network: 10.10.15.0/24
- Accessible to all VPN peers through jlo
- No NAT required - jlo is already the default gateway for this network

## Configuration Strategy

### Hub Configuration (jlo)

**Key Requirements:**
- Listen on public interface (UDP - custom port for obscurity)
- Accept connections from known peers (portaptty, android)
- Route traffic between wg0 and em0 (LAN interface)
- Handle intermittent peer connections gracefully

**OpenBSD-Specific Considerations:**
- Use native `wg(4)` driver (no wireguard-tools needed)
- Configure via `hostname.wg0` for persistence
- Update `pf.conf` to allow WireGuard traffic and forwarding
- Enable IP forwarding: `sysctl net.inet.ip.forwarding=1`

**AllowedIPs for jlo peers:**
```
# portaptty peer (laptop)
AllowedIPs = 10.10.16.2/32

# android peer (phone)
AllowedIPs = 10.10.16.3/32
```

### Road Warrior Configuration (portaptty)

**Key Requirements:**
- Managed in separate ansible repository (laptop-specific)
- Use `wg-quick` for easy up/down management
- Split-tunnel: Only route homelab traffic through VPN

**AllowedIPs for portaptty:**
```
# jlo as peer - only route homelab networks through VPN (split-tunnel)
AllowedIPs = 10.10.15.0/24, 10.10.16.0/24
```

**Notes:**
- Laptop won't always be connected - jlo handles this gracefully
- Split-tunnel only - internet traffic uses normal routing, only homelab goes through VPN

### Android Phone Configuration

**Key Requirements:**
- Intermittent connection (when away from home)
- Access to homelab LAN and other VPN peers
- Simple on/off control via app
- Split-tunnel: Only route homelab traffic through VPN

**Setup Method:**
- Use official WireGuard Android app (available on F-Droid or Play Store)
- App has built-in key generation (secure, keys never leave device)
- Import configuration via QR code or config file

**AllowedIPs for android:**
```
# jlo as peer - only route homelab networks through VPN (split-tunnel)
AllowedIPs = 10.10.15.0/24, 10.10.16.0/24
```

**Configuration Generation:**
- Ansible can generate a client config file for easy import
- Generate QR code from config for scanning into app
- Or manually copy/paste config into app

**Notes:**
- No PersistentKeepalive needed (intermittent road warrior)
- Split-tunnel only - mobile data/WiFi traffic uses normal routing
- Public key must be extracted from app and added to ansible vars

## Routing Considerations

### On jlo (Hub)

**IP Forwarding:**
```
# /etc/sysctl.conf
net.inet.ip.forwarding=1
```

**Packet Filter Rules (`pf.conf`):**

```
# WireGuard interface
wg_if = "wg0"
wg_port = "51923"  # Custom port (configurable)
wg_net = "10.10.16.0/24"
lan_if = "em0"
lan_net = "10.10.15.0/24"

# Allow WireGuard on external interface
pass in on $ext_if proto udp to port $wg_port

# Allow forwarding between wg0 and LAN (no NAT needed)
pass in on $wg_if from $wg_net to $lan_net
pass out on $lan_if from $wg_net to $lan_net

# Allow return traffic
pass in on $lan_if from $lan_net to $wg_net
pass out on $wg_if from $lan_net to $wg_net

# Allow peer-to-peer VPN traffic (optional - for VPN peers to reach each other)
pass on $wg_if from $wg_net to $wg_net
```

**No NAT Required:**
- jlo is already the default gateway for 10.10.15.0/24
- LAN hosts will naturally route return traffic back through jlo
- VPN traffic can be routed directly without translation

### On Spoke Peers

**Routing:**
- Default gateway points to jlo (10.10.16.1) for homelab networks
- Configured via AllowedIPs in WireGuard

## Ansible Implementation Strategy

### Approach for jlo (Hub)

**Dedicated WireGuard Role:**
```
roles/
  wireguard_server/
    tasks/
      main.yml
      interface.yml
      firewall.yml
    templates/
      hostname.wg0.j2
      pf.conf.j2 (extend existing)
    vars/
      main.yml (peers list)
```

This keeps WireGuard configuration separate and modular, making it easier to maintain and potentially reuse for other hosts in the future.

### Key Management

**Security Strategy:**
- **Private keys:** Generated on each host, NEVER stored in ansible repo
- **Private keys:** Stored securely in Bitwarden vault for backup/recovery
- **Public keys:** Stored in ansible variables (plaintext is fine - they're public!)
- **Future:** Migrate to OpenBao for centralized secrets management

**Key Generation Per Host:**

On OpenBSD (jlo):
```bash
openssl rand -base64 32  # Private key
# Derive public key (use wg pubkey or online tools)
```

On Linux (portaptty, if using wg-quick):
```bash
wg genkey  # Private key
wg pubkey < private.key  # Public key
```

On Android:
- Use WireGuard app's built-in key generator
- Export public key from app settings

**Ansible Variables Structure:**
```yaml
# group_vars/all.yml or host_vars/
wireguard_port: 51923

wireguard_peers:
  portaptty:
    public_key: "BASE64_PUBLIC_KEY_HERE"
    vpn_ip: "10.10.16.2"
    allowed_ips: "10.10.16.2/32"
    persistent_keepalive: 0

  android:
    public_key: "BASE64_PUBLIC_KEY_HERE"
    vpn_ip: "10.10.16.3"
    allowed_ips: "10.10.16.3/32"
    persistent_keepalive: 0
```

**Private Key Deployment:**
- jlo: Place private key manually before ansible deployment (you'll generate and store in Bitwarden)
- portaptty: Managed independently in separate ansible repo
- android: Managed via WireGuard app (keys never leave device)

**Benefits:**
- No secrets in git repo (even encrypted)
- Each host owns its private key
- OpenBao integration path ready for future
- Clean separation of concerns

### Configuration Files

**hostname.wg0 Template:**
```
# Generated by Ansible - do not edit manually
inet 10.10.16.1 255.255.255.0
wgport {{ wireguard_port }}
wgkey {{ wireguard_private_key }}
{% for peer in wireguard_peers %}
wgpeer {{ peer.public_key }} wgaip {{ peer.allowed_ips }}{% if peer.persistent_keepalive > 0 %} wgpka {{ peer.persistent_keepalive }}{% endif %}
{% endfor %}
up
```

### Deployment Workflow

1. Generate keys on jlo (if not exists)
2. Deploy hostname.wg0 configuration
3. Update pf.conf with WireGuard rules
4. Enable IP forwarding via sysctl
5. Bring up wg0 interface: `sh /etc/netstart wg0`
6. Reload pf: `pfctl -f /etc/pf.conf`

## Testing Plan

### Phase 1: Hub Setup
1. Deploy WireGuard configuration to jlo
2. Verify wg0 interface is up: `ifconfig wg0`
3. Check listening port: `netstat -an | grep 51923`

### Phase 2: First Peer (portaptty)
1. Configure laptop manually (before automating)
2. Test connectivity: `ping 10.10.16.1`
3. Test LAN access: `ping 10.10.15.1`
4. Test access to other LAN hosts

### Phase 3: Second Peer (android)
1. Generate keys in WireGuard Android app
2. Add public key to ansible vars and redeploy jlo
3. Import client config into app via QR code
4. Test connectivity and LAN access from phone

### Phase 4: Validation
1. Verify routing with `traceroute`
2. Check firewall logs for blocked traffic
3. Test persistent connections and reconnection
4. Verify keepalive behavior

## Security Considerations

### Firewall Rules
- Only allow WireGuard port on external interface
- Use strict AllowedIPs for each peer
- Consider rate-limiting WireGuard port to prevent DoS
- Log and monitor WireGuard connection attempts

### Key Management
- Rotate keys periodically (manual process)
- Never commit private keys unencrypted
- Use separate keys for each peer
- Document key rotation procedure

### Network Segmentation
- Consider whether all VPN peers should access entire LAN
- May want to restrict certain peers to specific subnets/hosts
- Use pf rules for granular access control

### Monitoring
- Log WireGuard handshakes
- Monitor for unusual traffic patterns
- Track peer connection/disconnection events
- Alert on failed authentication attempts

## Future Enhancements

### Potential Improvements
1. **Additional Peers:** Easy to add more road warriors or permanent peers
2. **Dynamic Endpoint Discovery:** For peers behind dynamic IPs
3. **Backup VPN Server:** Redundant hub for high availability
4. **Split DNS:** Provide homelab DNS resolution to VPN clients
5. **Monitoring Dashboard:** Track peer connections and bandwidth usage
6. **Automatic Key Rotation:** Ansible-based key rotation procedure

### Integration with Existing Infrastructure
- **DNS:** Add internal DNS entries for VPN peers
- **Monitoring:** Integrate WireGuard metrics into monitoring system
- **Backup:** Include WireGuard configs in backup procedures
- **OpenBao Integration:**
  - Store private keys in OpenBao instead of Bitwarden
  - Ansible fetches keys from OpenBao during deployment
  - Centralized secrets management across homelab
  - Key rotation automation becomes possible
  - Note: VPN facilitates OpenBao deployment by enabling communication between nodes

## Decisions Made

1. **Port Selection:** ✅ Custom port (51923) for obscurity - configurable in ansible vars
2. **Key Generation:** ✅ Generate on each target host, store private keys in Bitwarden
3. **NAT Strategy:** ✅ No NAT needed - jlo is already the gateway, use routing only
4. **Public Key Storage:** ✅ Store in ansible vars (plaintext) - they're public keys
5. **Future Secrets:** ✅ Plan migration to OpenBao for centralized secrets management
6. **Private Key Handling:** ✅ User generates jlo key manually before deployment (option A)
7. **Split vs Full Tunnel:** ✅ Split-tunnel ONLY - route only 10.10.15.0/24 through VPN, not all traffic

## Open Questions

1. **Peer-to-Peer:** Enable direct peer-to-peer communication between VPN clients?
2. **DNS:** Should VPN clients use homelab DNS for internal name resolution?

## References

- [OpenBSD wg(4) Manual](https://man.openbsd.org/wg)
- [WireGuard on OpenBSD HOWTO](https://ianix.com/wireguard/openbsd-howto.html)
- [OpenBSD PF User's Guide](https://www.openbsd.org/faq/pf/)
