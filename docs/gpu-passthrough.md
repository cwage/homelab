# GPU Passthrough Setup

This documents the manual configuration required on Proxmox hosts to enable GPU passthrough to VMs. These steps are **not** managed by Ansible and must be performed manually when setting up a new Proxmox host for GPU passthrough.

## Prerequisites

- IOMMU-capable CPU (AMD-Vi or Intel VT-d)
- GPU in its own IOMMU group (check with `find /sys/kernel/iommu_groups/*/devices -type l`)

## Manual Steps on Proxmox Host

### 1. Enable IOMMU in GRUB

Edit `/etc/default/grub` and add IOMMU parameters:

```bash
# For AMD CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"

# For Intel CPUs:
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
```

Then update GRUB and reboot:
```bash
update-grub
reboot
```

### 2. Load VFIO Modules

Add to `/etc/modules`:
```
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

### 3. Create PCI Device Mapping

Proxmox requires a PCI mapping for non-root API tokens to assign devices. Create via:

```bash
# Get device info first
lspci -nn | grep -i nvidia

# Create mapping (adjust IDs for your GPU)
pvesh create /cluster/mapping/pci \
  --id gpu-gtx1050ti \
  --map "id=10de:1c82,node=pve,path=0000:07:00,iommugroup=14,subsystem-id=1462:8c96"
```

The mapping is stored in `/etc/pve/mapping/pci.cfg`.

### 4. Reboot

After all changes, reboot the Proxmox host:
```bash
reboot
```

Verify IOMMU is enabled:
```bash
dmesg | grep -e DMAR -e IOMMU
```

## Ansible-Managed Configuration

The following are managed by the `gpu_passthrough` Ansible role and applied automatically:

- `/etc/modprobe.d/vfio.conf` - Binds GPU device IDs to vfio-pci driver
- `/etc/modprobe.d/blacklist-gpu.conf` - Blacklists nouveau/nvidia drivers on host
- `update-initramfs -u` - Triggered when configs change

## VM Configuration

The VM must use:
- **Machine type**: q35 (for PCIe passthrough)
- **hostpci**: Reference the PCI mapping created above

This is managed by OpenTofu in `tofu/containers.tf`.

## Current Hardware

### pve1
- **GPU**: NVIDIA GeForce GTX 1050 Ti (10de:1c82)
- **Audio**: NVIDIA Audio Controller (10de:0fb9)
- **IOMMU Group**: 14 (GPU + Audio only, safe to pass through)
- **NIC IOMMU Group**: 13 (separate, not affected by GPU passthrough)

## Troubleshooting

### Network loss after reboot
If the host loses network after reboot, check `/etc/modprobe.d/` for any files blacklisting the NIC driver (e.g., `r8169`). The NIC must NOT be blacklisted.

### GPU not binding to vfio-pci
Check that the GPU device IDs in `/etc/modprobe.d/vfio.conf` match your hardware:
```bash
lspci -nn | grep -i nvidia
```
