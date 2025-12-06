# Repo strategy

Use three repos with clear boundaries:

openbsd-netcfg (network & security — high risk)

/etc/pf.conf, /etc/dhcpd.conf, /var/unbound/etc/local-data.conf

Tiny apply.sh or Ansible role to validate → reload

Kept private, stricter review (this one can lock you out)

homelab-infra (Proxmox itself + VM lifecycle — IaC)

OpenTofu: tofu/

modules/ (vm, lxc, network)

envs/prod/ (state backend, variables)

Ansible: ansible/

inventory/hosts.ini (pve node, services VM)

roles/pve/ (repo setup, users/tokens, storage, firewall)

roles/services_vm/ (base pkgs, mounts)

playbooks/ (pve-bootstrap.yml, services-vm.yml)

cloudinit/ templates

Makefile targets: make plan, make apply, make pve-bootstrap

Access: private; tokens limited to what each tool needs

homelab-stacks (apps on the services VM — day-to-day)

compose/<app>/compose.yml

deploy/ (systemd timer + deploy-stacks.sh)

secrets/ with sops+age

This one changes the most; easy to share selectively

# Homelab Plan: Proxmox + One “Services” VM + Sane DNS/DHCP

## 0) Assumptions
- Wired LAN (gig-e) for Proxmox host, NAS (Synology DS1815+), and core gear.
- OpenBSD firewall/router already running DHCP.
- Goal: run apps in **one Ubuntu VM** (Docker/Compose), store bulky data on NAS, keep networking simple.

---

## 1) Proxmox host (oldPC)

**Firmware**
- Update BIOS; enable **SVM/VT-x** + **IOMMU**.
- Optional later: swap Realtek NIC → **Intel i350/i210**.

**Install**
- Install **Proxmox VE 8** on the **SSD**.
- Create `vmbr0` bridging the wired NIC; assign Proxmox a static LAN IP.

**Add NAS storage (for backups/ISO/templates)**
```bash
# Example: add Synology NFS export as Proxmox storage
pvesm add nfs syno-backups \
  --server <NAS_IP> \
  --export /volume1/proxmox-backups \
  --content backup,iso,vztmpl \
  --options vers=4.1
```

---

## 2) “Services” VM (Ubuntu 24.04 LTS)

**Create**
- 6 vCPU / 16–24 GB RAM / 120–200 GB disk (on SSD).
- VirtIO for NIC/disk; enable **QEMU guest agent**.

**Base packages**
```bash
sudo apt update
sudo apt install -y qemu-guest-agent docker.io docker-compose-plugin \
                    git nfs-common tmux
sudo systemctl enable --now qemu-guest-agent docker
sudo usermod -aG docker $USER
```

**Mount NAS (bulky data only)**
```bash
sudo mkdir -p /mnt/nfs/{media,appdata}
echo '<NAS_IP>:/volume1/appdata  /mnt/nfs/appdata  nfs4  rw,vers=4.1,noatime,hard,timeo=600,nconnect=4  0  0' | sudo tee -a /etc/fstab
echo '<NAS_IP>:/volume1/media    /mnt/nfs/media    nfs4  rw,vers=4.1,noatime,hard,timeo=600,nconnect=4  0  0' | sudo tee -a /etc/fstab
sudo mount -a
```
> Keep databases/anything write-heavy on the VM’s **local disk**. Use NAS for static/blobby stuff and backups.

**Option A — Portainer CE (dashboard + Git stacks)**
```bash
docker volume create portainer_data
docker run -d --name portainer --restart=always \
  -p 9000:9000 -p 9443:9443 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v portainer_data:/data \
  portainer/portainer-ce:latest
# In Portainer: Stacks → Create from Git (point at your repo)
```

**Option B — Simple Git-driven Compose deploy (systemd timer)**
```bash
sudo mkdir -p /srv/compose
sudo tee /usr/local/bin/deploy-stacks.sh >/dev/null <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /srv/compose
git pull --ff-only || true
for d in */ ; do
  [ -f "$d/compose.yml" ] || continue
  docker compose -f "$d/compose.yml" pull
  docker compose -f "$d/compose.yml" up -d --remove-orphans
done
EOF
sudo chmod +x /usr/local/bin/deploy-stacks.sh

sudo tee /etc/systemd/system/compose-gitops.service >/dev/null <<'EOF'
[Unit]
Description=Pull compose repo and deploy stacks
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/deploy-stacks.sh
EOF

sudo tee /etc/systemd/system/compose-gitops.timer >/dev/null <<'EOF'
[Unit]
Description=Run compose GitOps every 5 minutes
[Timer]
OnBootSec=2m
OnUnitActiveSec=5m
Unit=compose-gitops.service
[Install]
WantedBy=timers.target
EOF

sudo systemctl enable --now compose-gitops.timer
```

---

## 3) Storage strategy
- **Local (VM disk):** databases, indexes, write-heavy volumes.
- **NAS (NFS mounts):** media/downloads/backups/attachments/static blobs.
- **Backups:** Proxmox VM backups → Synology NFS (`syno-backups` storage).  
  Inside the VM, use **restic**/**borg** to NAS or cloud.

---

## 4) DHCP/DNS plan

**Keep DHCP on OpenBSD** (boots first, least moving parts).

**Internal DNS name**
- Prefer a subdomain you own, e.g. **`home.quietlife.net`** (or the reserved `home.arpa`).
- Avoid `.local` (mDNS) and avoid `.lan`.

**Resolvers**
- **Primary:** **Unbound** on the OpenBSD firewall (recursive + caching + local overrides).
- **Secondary:** **Unbound** or **AdGuard Home** on the services VM.  
  Hand out **both** IPs via DHCP so clients survive a VM outage.

**OpenBSD `dhcpd.conf` (essentials)**
```conf
option domain-name "home.quietlife.net";
option domain-search "home.quietlife.net";
option domain-name-servers 10.10.10.1, 10.10.10.20;  # firewall first, VM second
option routers 10.10.10.1;
# pools/reservations as needed...
```

**Unbound on the firewall (local overrides)**
```conf
server:
    interface: 10.10.10.1
    access-control: 10.10.10.0/24 allow
    qname-minimisation: yes
    prefetch: yes
    harden-dnssec-stripped: yes

    # Split-DNS for internal names
    local-zone: "home.quietlife.net." transparent
    local-data: "nas.home.quietlife.net. A 10.10.10.30"
    local-data: "services.home.quietlife.net. A 10.10.10.20"
    local-data-ptr: "10.10.10.30 nas.home.quietlife.net."
    local-data-ptr: "10.10.10.20 services.home.quietlife.net."
```
> Keep the local-data records in an include file under Git; `unbound-control reload` on change.

**Optional — DHCP→DNS auto-registration**
- Swap DHCP to **dnsmasq** on the firewall (lightweight; auto-exports leases to DNS).  
  Not required if static reservations + a few local-data records are fine.

---

## 5) Optional add-ons (later)
- NIC upgrade (Intel) for fewer driver quirks.
- Add a second SSD or NVMe (via PCIe adapter) for mirrored VM storage.
- Use the GTX 1050 Ti for **NVENC** in Jellyfin/HandBrake containers/VMs.
- K8s: spin **k3s** inside the services VM only when needed; keep most workloads on Compose.

---

## 6) Quick checklist
1. Wire the host → switch (gig-e).  
2. Install **Proxmox** on SSD; create `vmbr0`; add Synology NFS storage.  
3. Create **Ubuntu 24.04 “services” VM**; install Docker/Compose; mount NAS paths.  
4. Choose **Portainer** _or_ the **GitOps script** for Compose deploys.  
5. On OpenBSD: keep **DHCP**; set domain/search; hand out **two DNS servers**.  
6. Configure **Unbound** on firewall with local overrides for `home.quietlife.net`.  
7. (Optional) Add secondary resolver on the VM; add a few static DHCP reservations.  
8. Put **DBs on VM disk**, **bulk on NAS**, **backups to NAS** via Proxmox + restic/borg.  

---

**End of plan.**
