# Proxmox GPU Passthrough Fuckup - December 2025

## Summary

After making BIOS changes for GPU passthrough on the Proxmox host (`10.10.15.18`), the machine rebooted and had no network connectivity. The NIC appeared to be configured correctly on `vmbr0` but couldn't reach the network.

## Hardware

- **Motherboard**: Gigabyte AX370-Gaming-CF
- **CPU**: Ryzen 7 1800X
- **NIC**: Realtek PCIe Gigabit Ethernet (driver: `r8169`)
- **GPU**: NVIDIA GeForce GTX 1050 Ti

## Root Cause

A previous Claude chat session helping with GPU passthrough for Docker containers had **blacklisted the r8169 NIC driver** in `/etc/modprobe.d/blacklist-r8169.conf`. This was likely done as part of a VFIO passthrough guide without understanding it would kill network connectivity.

The BIOS changes + reboot caused the blacklist to take effect (it may have been added but not applied until the reboot).

## Symptoms

1. Machine boots but hangs waiting for NFS mounts to timeout (no network)
2. Once at console, `vmbr0` shows UP with correct IP (`10.10.15.18`)
3. No physical NIC interface visible in `ip addr` or `ls /sys/class/net/`
4. `lspci | grep -i net` shows the Realtek controller exists at PCI address `04:00.0`
5. `lspci -k -s 04:00.0` shows `r8169` driver is associated but...
6. `dmesg | grep r8169` shows **nothing** - driver never initialized

## Red Herrings

- USB ethernet adapter was plugged in from previous troubleshooting attempt, showed up as `enx9cebe8ed559e` (MAC-based naming for USB NICs)
- Thought it was a BIOS issue with onboard NIC disabled
- Spent time searching for IOMMU settings in BIOS (Gigabyte BIOS is confusing)

## The Fix

1. **Manually load the driver** to restore connectivity:
   ```bash
   modprobe -r r8169 && modprobe r8169
   ```
   This brought up `enp4s0` immediately.

2. **Remove the blacklist file**:
   ```bash
   sudo rm /etc/modprobe.d/blacklist-r8169.conf
   ```

3. **Update initramfs**:
   ```bash
   sudo update-initramfs -u
   ```

4. **Reboot** to verify fix persists.

## Files Involved

- `/etc/modprobe.d/blacklist-r8169.conf` - contained `blacklist r8169` (DELETED)
- `/etc/modprobe.d/r8169-options.conf` - just a comment, no actual options
- `/etc/modules` - had VFIO modules listed for GPU passthrough:
  ```
  vfio
  vfio_iommu_type1
  vfio_pci
  vfio_virqfd
  ```
- `/etc/network/interfaces` - bridge config, `bridge-ports enp4s0`

## Lessons Learned

1. **Never blindly blacklist drivers** from GPU passthrough guides without understanding what they do
2. The r8169 blacklist was probably intended for a different system or copied from a guide where the NIC was Intel, not Realtek
3. USB ethernet adapters get weird `enx<MAC>` names, don't confuse them with onboard NICs
4. `lspci -k` shows driver association but doesn't mean the driver actually loaded - check `dmesg` for actual initialization
5. If `dmesg | grep <driver>` shows nothing, the driver module is blacklisted or failed to load

## Related Issues

- GitHub Issue #50: NFS mount timeout during boot when network unavailable (should add `nofail` or `x-systemd.automount` to NFS mounts)

## Debugging Commands Cheatsheet

```bash
# Check if NIC hardware is visible
lspci | grep -i net
lspci | grep -i realtek

# Check what driver is bound to NIC
lspci -k -s <PCI_ADDRESS>

# Check what network interfaces exist
ls /sys/class/net/
ip link show
ip addr show

# Check if driver actually initialized
dmesg | grep -i r8169
dmesg | grep -i <PCI_ADDRESS>

# Check for blacklists
cat /etc/modprobe.d/*.conf | grep blacklist
ls /etc/modprobe.d/

# Force driver reload
modprobe -r r8169 && modprobe r8169

# Check IOMMU groups (for passthrough debugging)
ls /sys/kernel/iommu_groups/*/devices/

# Check VFIO
dmesg | grep -i vfio
```

---

## A Message to My Past Self (The Other Claude Session)

Hey buddy. We need to talk.

You blacklisted `r8169`. The **only network interface** on this machine. The one thing standing between a working Proxmox host and a very expensive paperweight.

I get it - you were following a GPU passthrough guide. Those guides love to say "blacklist all the drivers!" without mentioning that maybe, just maybe, you should check if any of those drivers are **keeping the system connected to the network**.

Here's a pro tip for next time: before you blacklist a driver, run `lspci -k` and see what's actually using it. If it's the NIC, maybe don't do that.

The user had to:
1. Wait for NFS timeouts on a headless server
2. Plug in a USB keyboard
3. Debug from the console
4. Spend an hour figuring out why the NIC wasn't showing up
5. Discover YOUR blacklist file

All because you didn't check what `r8169` was for.

For GPU passthrough, you only need to blacklist the **GPU drivers** (nouveau, nvidia, nvidiafb). Not random network drivers. The GPU doesn't need the network card's driver. They're not friends. They don't hang out.

Do better.

- Claude (the one who had to clean up your mess)
