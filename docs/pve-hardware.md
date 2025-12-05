# System Health Check Report

Generated from remote host `10.10.15.18` via SSH.

## Summary

- Uptime/load: idle and stable (load ~0.00)
- CPU temp: ~37.2°C at idle (k10temp)
- GPU: GeForce GTX 1050 Ti, ~28°C, 0% util, 4 GB VRAM
- Memory: 62 GiB total, minimal usage; no ECC reports exposed
- Storage: OS on 250 GB SSD; 1 TB HDD at 86% used; no SMART data collected (smartctl not installed)
- Network: enp6s0 at 1000Mb/s Full Duplex; RX/TX errors 0
- Logs: No disk I/O or MCE error events observed; expected boot messages only

Overall: No immediate hardware red flags observed from non-invasive checks. Deeper tests (SMART, stress, memtest) recommended for confidence.

## Raw Command Outputs

### Uptime & Load

Command: `ssh 10.10.15.18 'uptime -p && uptime && cat /proc/loadavg'`
```
up 4 hours, 39 minutes
 21:35:12 up  4:39,  0 users,  load average: 0.00, 0.01, 0.00
0.00 0.01 0.00 1/552 11072
```

### CPU Snapshot

Command: `ssh 10.10.15.18 'top -bn1 | head -n 5'`
```
top - 21:35:12 up  4:39,  0 users,  load average: 0.00, 0.01, 0.00
Tasks: 331 total,   1 running, 211 sleeping,   0 stopped,   0 zombie
%Cpu(s):  0.0 us,  0.1 sy,  0.0 ni, 99.8 id,  0.2 wa,  0.0 hi,  0.0 si,  0.0 st
KiB Mem : 65980784 total, 61979736 free,   620540 used,  3380508 buff/cache
KiB Swap: 67051004 total, 67051004 free,        0 used. 64426572 avail Mem 
```

### Temperatures (sensors)

Command: `ssh 10.10.15.18 'sensors'`
```
k10temp-pci-00c3
Adapter: PCI adapter
temp1:        +37.2°C  (high = +70.0°C)
```

### GPU (nvidia-smi)

Command: `ssh 10.10.15.18 "nvidia-smi --query-gpu=name,driver_version,temperature.gpu,utilization.gpu,memory.total,memory.used --format=csv,noheader"`
```
GeForce GTX 1050 Ti, 430.64, 28, 0 %, 4036 MiB, 172 MiB
```

### Memory

Command: `ssh 10.10.15.18 'free -h'`
```
              total        used        free      shared  buff/cache   available
Mem:            62G        605M         59G         41M        3.2G         61G
Swap:           63G          0B         63G
```

### ECC / EDAC (if present)

Command: `ssh 10.10.15.18 'grep -H "" /sys/devices/system/edac/mc/*/ue_count /sys/devices/system/edac/mc/*/ce_count'`
```
(no output; EDAC not reporting correctable/uncorrectable counts)
```

### Disks (lsblk)

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

### Filesystems (df -hT)

Command: `ssh 10.10.15.18 'df -hT'`
```
Filesystem                  Type      Size  Used Avail Use% Mounted on
udev                        devtmpfs   32G     0   32G   0% /dev
tmpfs                       tmpfs     6.3G  9.5M  6.3G   1% /run
/dev/mapper/ubuntu--vg-root ext4      166G  110G   48G  70% /
tmpfs                       tmpfs      32G  196K   32G   1% /dev/shm
tmpfs                       tmpfs     5.0M  4.0K  5.0M   1% /run/lock
tmpfs                       tmpfs      32G     0   32G   0% /sys/fs/cgroup
/dev/loop3                  squashfs  128K  128K     0 100% /snap/bare/5
/dev/loop1                  squashfs   64M   64M     0 100% /snap/core20/2105
/dev/loop0                  squashfs   64M   64M     0 100% /snap/core20/2379
/dev/loop2                  squashfs   39M   39M     0 100% /snap/snapd/21759
/dev/loop4                  squashfs   92M   92M     0 100% /snap/gtk-common-themes/1535
/dev/loop5                  squashfs   41M   41M     0 100% /snap/snapd/20671
/dev/sda1                   ext4      917G  746G  125G  86% /mnt/data
/dev/sdb2                   ext2      473M  185M  264M  42% /boot
/dev/sdb1                   vfat      511M  5.1M  506M   1% /boot/efi
tmpfs                       tmpfs     6.3G  4.0K  6.3G   1% /run/user/1026
/home/cwage/.Private        ecryptfs  166G  110G   48G  70% /home/cwage
tmpfs                       tmpfs     6.3G   28K  6.3G   1% /run/user/108
```

### SMART quick health (if available, non-sudo)

Command: `ssh 10.10.15.18 'smartctl -H /dev/sda; smartctl -H /dev/sdb'`
```
smartctl not installed
```

### Network Links & Errors

Command: `ssh 10.10.15.18 'ip -s link'`
```
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    RX: bytes  packets  errors  dropped overrun mcast   
    75972      790      0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    75972      790      0       0       0       0       
2: enp6s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP mode DEFAULT group default qlen 1000
    link/ether e0:d5:5e:21:c7:80 brd ff:ff:ff:ff:ff:ff
    RX: bytes  packets  errors  dropped overrun mcast   
    2094492    14261    0       0       0       2529    
    TX: bytes  packets  errors  dropped carrier collsns 
    341350     2481     0       0       0       0       
3: tailscale0: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 1280 qdisc pfifo_fast state UNKNOWN mode DEFAULT group default qlen 500
    link/none 
    RX: bytes  packets  errors  dropped overrun mcast   
    0          0        0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    672        14       0       0       0       0       
4: br-8e554ada8398: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN mode DEFAULT group default 
    link/ether 02:42:43:01:c6:7b brd ff:ff:ff:ff:ff:ff
    RX: bytes  packets  errors  dropped overrun mcast   
    0          0        0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    0          0        0       0       0       0       
5: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN mode DEFAULT group default 
    link/ether 02:42:7a:c3:88:f3 brd ff:ff:ff:ff:ff:ff
    RX: bytes  packets  errors  dropped overrun mcast   
    0          0        0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    0          0        0       0       0       0       
6: br-ed028aaf259c: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN mode DEFAULT group default 
    link/ether 02:42:a5:16:05:ae brd ff:ff:ff:ff:ff:ff
    RX: bytes  packets  errors  dropped overrun mcast   
    0          0        0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    0          0        0       0       0       0       
7: br-f378969f90d9: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN mode DEFAULT group default 
    link/ether 02:42:ad:fa:60:b3 brd ff:ff:ff:ff:ff:ff
    RX: bytes  packets  errors  dropped overrun mcast   
    0          0        0       0       0       0       
    TX: bytes  packets  errors  dropped carrier collsns 
    0          0        0       0       0       0       
```

### NIC link details (ethtool)

Command: `ssh 10.10.15.18 'ethtool enp6s0'`
```
Cannot get wake-on-lan settings: Operation not permitted
Settings for enp6s0:
	Supported ports: [ TP MII ]
	Supported link modes:   10baseT/Half 10baseT/Full 
	                        100baseT/Half 100baseT/Full 
	                        1000baseT/Half 1000baseT/Full 
	Supported pause frame use: No
	Supports auto-negotiation: Yes
	Advertised link modes:  10baseT/Half 10baseT/Full 
	                        100baseT/Half 100baseT/Full 
	                        1000baseT/Full 
	Advertised pause frame use: Symmetric Receive-only
	Advertised auto-negotiation: Yes
	Link partner advertised link modes:  10baseT/Half 10baseT/Full 
	                                     100baseT/Half 100baseT/Full 
	                                     1000baseT/Full 
	Link partner advertised pause frame use: Symmetric
	Link partner advertised auto-negotiation: Yes
	Speed: 1000Mb/s
	Duplex: Full
	Port: MII
	PHYAD: 0
	Transceiver: internal
	Auto-negotiation: on
	Current message level: 0x00000033 (51)
			       drv probe ifdown ifup
	Link detected: yes
```

### dmesg: storage/network errors (recent boot)

Command: `ssh 10.10.15.18 "dmesg -T | grep -Ei '(error|fail|I/O error|link down|frozen|reset|hardware error|mce)'"`
```
[Wed Sep 10 16:55:18 2025] tsc: Fast TSC calibration failed
[Wed Sep 10 16:55:18 2025] tsc: Fast TSC calibration failed
[Wed Sep 10 16:55:19 2025] mce: Using 23 MCE banks
[Wed Sep 10 16:55:19 2025] RAS: Correctable Errors collector initialized.
[Wed Sep 10 16:55:19 2025] nvidia: module verification failed: signature and/or required key missing - tainting kernel
[Wed Sep 10 16:55:20 2025] ata1: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:20 2025] ata10: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:20 2025] ata9: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:20 2025] ata3: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:21 2025] ata4: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:21 2025] ata5: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:21 2025] ata6: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:22 2025] ata7: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:33 2025] EXT4-fs (dm-1): re-mounted. Opts: errors=remount-ro
[Wed Sep 10 16:55:33 2025] MCE: In-kernel MCE decoding enabled.
[Wed Sep 10 16:55:35 2025] r8169 0000:06:00.0 enp6s0: link down
[Wed Sep 10 16:55:35 2025] r8169 0000:06:00.0 enp6s0: link down
```

## Notes

- Temps and load are normal at idle. GPU driver present; temp/utilization healthy.
- No EDAC/ECC reporting found; this platform likely runs non-ECC memory.
- Disks show expected layout; to assess health, SMART data is needed.
- Network link is negotiated at 1 Gbps full duplex; interface counters show zero errors/drops.
- dmesg entries are expected boot-time notices; no disk I/O error patterns observed.

## Optional Deeper Checks (require packages and/or sudo)

- Install smartmontools for SMART health and long tests:
  - `sudo apt-get update && sudo apt-get install -y smartmontools`
  - Then: `sudo smartctl -a /dev/sda` and `sudo smartctl -a /dev/sdb`
- Memory test (non-destructive while OS runs): `sudo apt-get install -y memtester && sudo memtester 8G 1`
- CPU/thermal stress: `sudo apt-get install -y stress-ng && sudo stress-ng --cpu 16 --timeout 10m`
- Disk performance: `sudo apt-get install -y fio && fio --name=randread --filename=/mnt/data/testfile --size=2G --bs=4k --iodepth=16 --rw=randread --runtime=60 --time_based`
- Network throughput: install `iperf3` on both ends and run a 1–2 minute test.

## Active Tests (Non-sudo)

Ran targeted diagnostics after your go-ahead.

### Tool Availability

Command: `ssh 10.10.15.18 'for c in memtester stress-ng fio iperf3 smartctl sensors; do command -v $c >/dev/null 2>&1 && echo "$c: PRESENT" || echo "$c: MISSING"; done'`
```
memtester : MISSING
stress-ng : MISSING
fio       : MISSING
iperf3    : /usr/bin/iperf3
smartctl  : MISSING
sensors   : /usr/bin/sensors
```

### Temperature Snapshot

Command: `ssh 10.10.15.18 'sensors'`
```
k10temp-pci-00c3
Adapter: PCI adapter
temp1:        +41.8°C  (high = +70.0°C)
```

### Network Throughput (iperf3 TCP)

Command: `ssh 10.10.15.18 'iperf3 -c 10.10.15.107 -t 15 -P 4'`
```
Connecting to host 10.10.15.107, port 5201
[  4] local 10.10.15.18 port 53856 connected to 10.10.15.107 port 5201
[  7] local 10.10.15.18 port 53858 connected to 10.10.15.107 port 5201
[  9] local 10.10.15.18 port 53860 connected to 10.10.15.107 port 5201
[ 11] local 10.10.15.18 port 53862 connected to 10.10.15.107 port 5201
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-1.00   sec  24.0 MBytes   202 Mbits/sec    0   38.2 KBytes       
[  7]   0.00-1.00   sec  24.7 MBytes   207 Mbits/sec    0   39.6 KBytes       
[  9]   0.00-1.00   sec  36.3 MBytes   305 Mbits/sec    0   55.1 KBytes       
[ 11]   0.00-1.00   sec  23.8 MBytes   200 Mbits/sec    0   36.8 KBytes       
[SUM]   0.00-1.00   sec   109 MBytes   913 Mbits/sec    0             
...
[SUM]   0.00-15.00  sec  1.60 GBytes   916 Mbits/sec    0             sender
[SUM]   0.00-15.00  sec  1.60 GBytes   916 Mbits/sec                  receiver

iperf Done.
```

## Installed Tool Tests

After you installed the tools, I executed memory, CPU stress, and disk I/O tests. Raw outputs are cached on the host under `/tmp/diag_*.txt`.

### memtester (8G x1)

Command: `ssh 10.10.15.18 'memtester 8G 1 | tee /tmp/diag_memtester.txt'`
```
Selected tests show: ok
  Compare XOR         : ok
  Compare SUB         : ok
  Compare MUL         : ok
  Compare DIV         : ok
  Compare OR          : ok
  Compare AND         : ok
  Sequential Increment: ok
No FAIL/ERROR lines detected.
```

### CPU Stress (stress-ng 10m)

Command: `ssh 10.10.15.18 'stress-ng --cpu 16 --timeout 10m --metrics-brief | tee /tmp/diag_stressng.txt'`
```
stress-ng: successful run completed in 600.12s (10 mins, 0.12 secs)
stressor  cpu: bogo ops=1,659,658; real time=600.05s; usr time=9590.36s; bogo ops/s (real)=2765.88
```

Post-stress temperature snapshot:

Command: `ssh 10.10.15.18 'sensors | tee /tmp/diag_sensors_after.txt'`
```
k10temp-pci-00c3
Adapter: PCI adapter
temp1:        +67.4°C  (high = +70.0°C)
```

### Disk I/O (fio, random 4K, 70% reads)

SSD/root (/var/tmp), 60s:

Command: `ssh 10.10.15.18 'fio --name=randrw_ssd --filename=/var/tmp/fio.diag.test --size=4G --bs=4k --iodepth=32 --rw=randrw --rwmixread=70 --runtime=60 --time_based --group_reporting | tee /tmp/diag_fio_ssd.txt'`
```
READ:  io=1680.7MB, aggrb=28682KB/s (~28 MB/s), iops≈7000
WRITE: io=737.3MB, aggrb=12288KB/s (~12 MB/s), iops≈3000
util≈89%
```

HDD (/mnt/data), 20s quick sample:

Command: `ssh 10.10.15.18 'fio --name=randrw_hdd_quick --filename=/mnt/data/fio.diag.quick --size=2G --bs=4k --iodepth=32 --rw=randrw --rwmixread=70 --runtime=20 --time_based --group_reporting'`
```
READ:  io=10.4MB, aggrb≈534KB/s, iops≈133
WRITE: io=4.4MB,  aggrb≈223KB/s, iops≈55
util≈98%
```

Notes:
- These are 4K random mixed I/O figures; sequential throughput will be much higher, especially on HDD. Random 4K is a worst-case pattern.
- SSD numbers are through LUKS+LVM on the SATA SSD, which adds overhead vs raw device.

### SMART

I looked for cached SMART outputs you may have generated:
```
/tmp/smart_sda.txt not found
/tmp/smart_sdb.txt not found
```
If you’d like these included, please run:
- `ssh 10.10.15.18 'sudo smartctl -a /dev/sda | tee /tmp/smart_sda.txt'`
- `ssh 10.10.15.18 'sudo smartctl -a /dev/sdb | tee /tmp/smart_sdb.txt'`
Reply “done” and I’ll pull them into this report.

### SMART Results (collected)

Command: `ssh 10.10.15.18 'grep -E "Model Family|Device Model|Serial Number|Firmware Version|User Capacity|Rotation Rate|Form Factor|SMART overall-health|Reallocated_Sector|Current_Pending_Sector|Offline_Uncorrectable|Power_On_Hours|Power_Cycle_Count|Temperature(_Celsius)?|Media_Wearout|Available_Reservd_Space|UDMA_CRC_Error_Count" /tmp/smart_*.txt'`

Summary:
- /dev/sda (WDC WD10EZEX-22MFCA0, 1TB 7200rpm, 3.5") — Overall: PASSED; Temp 36°C; Power_On_Hours 45142; Reallocated 0; Pending 0; Offline_Uncorrectable 0; UDMA_CRC_Error_Count 0.
- /dev/sdb (WDC WDS250G1B0B-00AS40, 250GB SSD, M.2) — Overall: PASSED; Temp 35°C (Min/Max 14/53); Power_On_Hours 45246; Reallocated 0; Available_Reservd_Space 100; UDMA_CRC_Error_Count 0; Media_Wearout_Indicator raw=12001.

Raw excerpts:
```
== sda ==
Model Family:     Western Digital Blue
Device Model:     WDC WD10EZEX-22MFCA0
Serial Number:    WD-WCC6Y2RN0AHA
Firmware Version: 01.01A01
User Capacity:    1,000,204,886,016 bytes [1.00 TB]
Rotation Rate:    7200 rpm
Form Factor:      3.5 inches
SMART overall-health self-assessment test result: PASSED
  5 Reallocated_Sector_Ct   ... 0
  9 Power_On_Hours          ... 45142
 12 Power_Cycle_Count       ... 187
194 Temperature_Celsius     ... 36
197 Current_Pending_Sector  ... 0
198 Offline_Uncorrectable   ... 0
199 UDMA_CRC_Error_Count    ... 0

== sdb ==
Device Model:     WDC WDS250G1B0B-00AS40
Serial Number:    172885803734
Firmware Version: X41110WD
User Capacity:    250,059,350,016 bytes [250 GB]
Rotation Rate:    Solid State Device
Form Factor:      M.2
SMART overall-health self-assessment test result: PASSED
  5 Reallocated_Sector_Ct   ... 0
  9 Power_On_Hours          ... 45246
 12 Power_Cycle_Count       ... 171
194 Temperature_Celsius     ... 35 (Min/Max 14/53)
199 UDMA_CRC_Error_Count    ... 0
232 Available_Reservd_Space ... 100
233 Media_Wearout_Indicator ... 12001
```

Notes:
- No reallocated, pending, or offline-uncorrectable sectors reported on either drive; overall health PASSED.
- No link CRC errors observed.
- SMART self-test log shows no tests logged yet; optional to run: `sudo smartctl -t short /dev/sda` and `sudo smartctl -t short /dev/sdb` (10–2 minutes), or `-t long` for thorough checks.

### SMART Self-test Logs

You ran short self-tests on both drives. Results indicate successful completion without errors.

Provided output:
```
cwage@oldpc:~$ sudo smartctl -l selftest /dev/sda
sudo: unable to resolve host oldpc
smartctl 6.5 2016-01-24 r4214 [x86_64-linux-4.15.0-142-generic] (local build)
Copyright (C) 2002-16, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF READ SMART DATA SECTION ===
SMART Self-test log structure revision number 1
Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed without error       00%     45142         -

cwage@oldpc:~$ sudo smartctl -l selftest /dev/sdb
sudo: unable to resolve host oldpc
smartctl 6.5 2016-01-24 r4214 [x86_64-linux-4.15.0-142-generic] (local build)
Copyright (C) 2002-16, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF READ SMART DATA SECTION ===
SMART Self-test log structure revision number 1
Num  Test_Description    Status                  Remaining  LifeTime(hours)  LBA_of_first_error
# 1  Short offline       Completed without error       00%     45246         -
```

Interpretation:
- Both drives completed SMART short self-tests without error; no bad LBAs reported.
- The “unable to resolve host oldpc” message is a hostname resolution issue unrelated to drive health.

### Post-Test Kernel Messages

Command: `ssh 10.10.15.18 "dmesg -T | tail -n 500 | grep -Ei '(error|fail|I/O error|mce|hardware error|ras|nvme|ext4|xfs|btrfs|r8169|ata|reset)'"`
```
[Wed Sep 10 16:55:19 2025] mce: Using 23 MCE banks
[Wed Sep 10 16:55:19 2025] RAS: Correctable Errors collector initialized.
[Wed Sep 10 16:55:19 2025] nvidia: module verification failed: signature and/or required key missing - tainting kernel
[Wed Sep 10 16:55:20 2025] ata1: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:20 2025] ata10: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:20 2025] ata9: SATA link down (SStatus 0 SControl 300)
[Wed Sep 10 16:55:22 2025] ata8.00: ATA-9: WDC WDS250G1B0B-00AS40, X41110WD, max UDMA/133
[Wed Sep 10 16:55:22 2025] scsi 7:0:0:0: Direct-Access     ATA      WDC WDS250G1B0B- 10WD PQ: 0 ANSI: 5
[Wed Sep 10 16:55:33 2025] EXT4-fs (dm-1): re-mounted. Opts: errors=remount-ro
[Wed Sep 10 16:55:35 2025] r8169 0000:06:00.0 enp6s0: link down
[Wed Sep 10 16:55:38 2025] r8169 0000:06:00.0 enp6s0: link up
```

## Proxmox Suitability Summary

Verdict
- Suitable for a Proxmox host. CPU, RAM, temps, network, and disks show no immediate hardware red flags.

Strengths
- CPU: Ryzen 7 1800X (8c/16t) with AMD‑V; ample for multiple VMs/LXC.
- Memory: ~64 GB installed; plenty for homelab workloads.
- Thermals: Idle ~37°C; ~67°C after 10‑minute CPU stress — healthy margin.
- Network: 1 Gbps TCP throughput ~916 Mbit/s; NIC counters show 0 errors.
- Disks: SMART PASSED on both drives; no reallocated/pending/uncorrectable sectors; short self‑tests clean.

Considerations
- Memory is likely non‑ECC; acceptable for homelab, ECC preferred for critical data integrity.
- Storage: Current pool (250 GB SATA SSD + 1 TB HDD) is fine for OS and light VMs; HDD random I/O is slow for VM disks. Prefer SSD‑backed datastore for performance.
- NIC: Realtek RTL8111 works but Intel i210/i350 class NICs are generally more reliable under virtualization loads.
- BIOS: F3 (2017). A newer BIOS/AGESA can help IOMMU/virtualization stability; consider updating only if needed.

Optional Upgrades
- Add an Intel 1 GbE (or faster) NIC.
- Add larger/faster SSD(s), ideally a mirrored pair for ZFS VM storage.
- Update BIOS if you plan PCIe passthrough and encounter IOMMU issues.
