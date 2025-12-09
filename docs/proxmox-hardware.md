# Hardware Inventory Report

Generated from remote host `10.10.15.18` via SSH.

## Summary

- Hostname: `oldpc`
- Kernel/Arch: `Linux 4.15.0-142-generic x86_64`
- System Vendor: Gigabyte Technology Co., Ltd.
- Product Name: AX370-Gaming
- Motherboard: AX370-Gaming-CF (Gigabyte Technology Co., Ltd.)
- BIOS: F3 (2017-06-19)
- CPU: AMD Ryzen 7 1800X (8 cores / 16 threads)
- Memory: 62 GiB total (64 GiB class)
- GPU: NVIDIA GeForce GTX 1050 Ti (GP107)
- Storage:
  - 250 GB SATA SSD — `WDC WDS250G1B0B-` (ROTA=0)
  - 1 TB SATA HDD — `WDC WD10EZEX-22M` (ROTA=1)
- Network: Realtek RTL8111/8168/8411 PCIe Gigabit (enp6s0)
- IP (enp6s0): `10.10.15.18/24`

## Raw Command Outputs

### Connectivity / Basics

Command: `ssh 10.10.15.18 'echo OK && hostname && uname -srmo'`

```
OK
oldpc
Linux 4.15.0-142-generic x86_64 GNU/Linux
```

### DMI / System Identity

Command: `ssh 10.10.15.18 'for f in sys_vendor product_name product_version product_family board_name board_vendor bios_version bios_date; do printf "%s: " "$f"; if [ -r "/sys/class/dmi/id/$f" ]; then cat "/sys/class/dmi/id/$f"; else echo N/A; fi; done'`

```
sys_vendor: Gigabyte Technology Co., Ltd.
product_name: AX370-Gaming
product_version: Default string
product_family: Default string
board_name: AX370-Gaming-CF
board_vendor: Gigabyte Technology Co., Ltd.
bios_version: F3
bios_date: 06/19/2017
```

### CPU

Command: `ssh 10.10.15.18 'lscpu'`

```
Architecture:          x86_64
CPU op-mode(s):        32-bit, 64-bit
Byte Order:            Little Endian
CPU(s):                16
On-line CPU(s) list:   0-15
Thread(s) per core:    2
Core(s) per socket:    8
Socket(s):             1
NUMA node(s):          1
Vendor ID:             AuthenticAMD
CPU family:            23
Model:                 1
Model name:            AMD Ryzen 7 1800X Eight-Core Processor
Stepping:              1
CPU MHz:               1883.614
CPU max MHz:           3600.0000
CPU min MHz:           2200.0000
BogoMIPS:              7199.10
Virtualization:        AMD-V
L1d cache:             32K
L1i cache:             64K
L2 cache:              512K
L3 cache:              8192K
NUMA node0 CPU(s):     0-15
Flags:                 fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb hw_pstate sme ssbd vmmcall fsgsbase bmi1 avx2 smep bmi2 rdseed adx smap clflushopt sha_ni xsaveopt xsavec xgetbv1 xsaves clzero irperf xsaveerptr arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif overflow_recov succor smca
```

### Memory

Command: `ssh 10.10.15.18 'free -h'`

```
              total        used        free      shared  buff/cache   available
Mem:            62G        587M         61G         41M        1.2G         61G
Swap:           63G          0B         63G
```

### Storage Devices

Command: `ssh 10.10.15.18 'lsblk -o NAME,TYPE,SIZE,MODEL,TRAN,ROTA,MOUNTPOINT'`

```
NAME                    TYPE    SIZE MODEL            TRAN   ROTA MOUNTPOINT
loop1                   loop   63.9M                            1 /snap/core20/2105
sdb                     disk  232.9G WDC WDS250G1B0B- sata      0 
├─sdb2                  part    488M                            0 /boot
├─sdb3                  part  231.9G                            0 
│ └─sdc3_crypt          crypt 231.9G                            0 
│   ├─ubuntu--vg-root   lvm     168G                            0 /
│   └─ubuntu--vg-swap_1 lvm      64G                            0 
│     └─cryptswap1      crypt    64G                            0 [SWAP]
└─sdb1                  part    512M                            0 /boot/efi
loop4                   loop   91.7M                            1 /snap/gtk-common-themes/1535
loop2                   loop   38.8M                            1 /snap/snapd/21759
loop0                   loop     64M                            1 /snap/core20/2379
sda                     disk  931.5G WDC WD10EZEX-22M sata      1 
└─sda1                  part  931.5G                            1 /mnt/data
loop5                   loop   40.4M                            1 /snap/snapd/20671
loop3                   loop      4K                            1 /snap/bare/5
```

Command: `ssh 10.10.15.18 'command -v nvme >/dev/null 2>&1 && nvme list || echo "nvme CLI not found"'`

```
nvme CLI not found
```

### PCI Summary (GPU / Storage / Network)

Command:
`ssh 10.10.15.18 'lspci -nn | grep -Ei "vga|3d|display"'`

```
09:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP107 [GeForce GTX 1050 Ti] [10de:1c82] (rev a1)
```

Command:
`ssh 10.10.15.18 'lspci -nn | grep -Ei "sata|nvme|raid|ahci|storage"'`

```
03:00.1 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] Device [1022:43b5] (rev 02)
12:00.2 SATA controller [0106]: Advanced Micro Devices, Inc. [AMD] FCH SATA Controller [AHCI mode] [1022:7901] (rev 51)
```

Command:
`ssh 10.10.15.18 'lspci -nn | grep -Ei "ethernet|network"'`

```
06:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. RTL8111/8168/8411 PCI Express Gigabit Ethernet Controller [10ec:8168] (rev 0c)
```

### USB Devices

Command: `ssh 10.10.15.18 'lsusb'`

```
Bus 006 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 005 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 004 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 003 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
Bus 001 Device 002: ID 067b:2303 Prolific Technology, Inc. PL2303 Serial Port
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
```

### Network Interfaces

Command: `ssh 10.10.15.18 'ip -br link'`

```
lo               UNKNOWN        00:00:00:00:00:00 <LOOPBACK,UP,LOWER_UP> 
enp6s0           UP             e0:d5:5e:21:c7:80 <BROADCAST,MULTICAST,UP,LOWER_UP> 
tailscale0       UNKNOWN        <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> 
br-8e554ada8398  DOWN           02:42:43:01:c6:7b <NO-CARRIER,BROADCAST,MULTICAST,UP> 
docker0          DOWN           02:42:7a:c3:88:f3 <NO-CARRIER,BROADCAST,MULTICAST,UP> 
br-ed028aaf259c  DOWN           02:42:a5:16:05:ae <NO-CARRIER,BROADCAST,MULTICAST,UP> 
br-f378969f90d9  DOWN           02:42:ad:fa:60:b3 <NO-CARRIER,BROADCAST,MULTICAST,UP> 
```

Command: `ssh 10.10.15.18 'ip -br addr'`

```
lo               UNKNOWN        127.0.0.1/8 ::1/128 
enp6s0           UP             10.10.15.18/24 fe80::e2d5:5eff:fe21:c780/64 
tailscale0       UNKNOWN        fe80::fa00:1b1a:e42d:ea71/64 
br-8e554ada8398  DOWN           172.21.0.1/24 
docker0          DOWN           172.17.0.1/16 
br-ed028aaf259c  DOWN           172.19.0.1/16 
br-f378969f90d9  DOWN           172.18.0.1/16 
```

## Notes

- The system appears to be an AM4 platform (Gigabyte AX370) with a Ryzen 7 1800X, 64 GB RAM class, and an NVIDIA GTX 1050 Ti.
- Storage includes a 250 GB SATA SSD and a 1 TB SATA HDD. No NVMe devices detected or `nvme` CLI not installed.
- Network uses a Realtek PCIe Gigabit NIC (enp6s0) and shows Docker/Tailscale virtual interfaces.
- This report ignores OS/software details per request.
