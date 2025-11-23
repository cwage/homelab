# Getting Started with Homelab

This guide walks you through setting up and using the homelab infrastructure from scratch. The homelab consists of two main components:
- **ansible/** — Configuration management for servers, firewalls, and network devices
- **tofu/** — VM provisioning on Proxmox using OpenTofu (Terraform fork)

## Prerequisites

### Required Software

- **Docker** (20.10 or later) and **Docker Compose** (v2)
  - All Ansible and OpenTofu operations run in containers
  - No local Ansible or OpenTofu installation needed
- **Make** — Command wrapper for all operations
- **Git** — For cloning and version control
- **SSH client** — For accessing managed hosts

### System Requirements

- **Development machine**: Linux, macOS, or WSL2 on Windows
- **Disk space**: ~5GB for Docker images and state files
- **Network access**: Connectivity to your Proxmox host and managed servers

### Infrastructure Requirements

Before you can manage your homelab, you need:

1. **Proxmox VE host** (if using OpenTofu)
   - Proxmox 7.x or 8.x installed
   - Network access from your development machine
   - API token credentials (see OpenTofu setup below)

2. **Managed hosts** with:
   - SSH access configured
   - A deploy user with sudo privileges
   - Python 3 installed (for Ansible, not required for OpenBSD hosts)

## Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/cwage/homelab.git
cd homelab
```

### 2. Choose Your Starting Point

- **Managing existing servers?** → Start with [Ansible Setup](#ansible-setup)
- **Provisioning VMs on Proxmox?** → Start with [OpenTofu Setup](#opentofu-setup)
- **Both?** → Set up OpenTofu first, then Ansible

## Ansible Setup

Ansible manages configuration for all hosts including firewalls, VPSs, and NAS devices.

### Step 1: Initialize Ansible Environment

```bash
cd ansible
make init
```

This creates `.env` and sets your UID/GID for proper file permissions in Docker.

### Step 2: Build the Ansible Container

```bash
make build
```

This builds the Ansible Docker image with all required collections.

### Step 3: Configure SSH Access

#### Create Deploy User on Target Hosts

On each managed host, create a `deploy` user with sudo access:

**For Debian/Ubuntu hosts:**
```bash
# On the target host
sudo adduser deploy
sudo usermod -aG sudo deploy
sudo mkdir -p /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
```

**For OpenBSD hosts:**
```bash
# On the firewall
doas useradd -m -G wheel deploy
doas mkdir -p /home/deploy/.ssh
doas chmod 700 /home/deploy/.ssh
```

#### Generate SSH Keys

```bash
# In the ansible/ directory
mkdir -p keys/deploy
ssh-keygen -t ed25519 -f keys/deploy/id_ed25519 -C "ansible-deploy" -N ""
chmod 600 keys/deploy/id_ed25519
chmod 644 keys/deploy/id_ed25519.pub

# Copy the public key to each host
ssh-copy-id -i keys/deploy/id_ed25519.pub deploy@<host-ip>
```

**Note**: The `keys/` directory is gitignored. Keep your private keys secure!

#### Create Public Key Symlink

For template creation and some roles:
```bash
cd keys
ln -s deploy/id_ed25519.pub deploy.pub
```

### Step 4: Configure Inventory

The inventory file defines which hosts Ansible manages. Edit `inventories/hosts.yml`:

```yaml
all:
  children:
    proxmox:
      hosts:
        pve1:
          ansible_host: 10.10.15.18
          ansible_port: 22
    openbsd_firewalls:
      hosts:
        fw1:
          ansible_host: 10.10.15.1
          ansible_port: 22
```

Adjust IP addresses and hostnames to match your infrastructure. See [inventory documentation](../ansible/docs/inventory-guide.md) for more details.

### Step 5: Test Connectivity

```bash
make ping
```

Expected output: Green `pong` responses from all hosts.

**If ping fails:**
- Verify SSH keys are properly installed: `ssh -i keys/deploy/id_ed25519 deploy@<host-ip>`
- Check `ansible.cfg` has correct paths (should work out of the box)
- Ensure target hosts have the deploy user configured

### Step 6: Verify Access and Privileges

```bash
make access_check
```

This verifies the deploy user can run sudo commands on managed hosts.

### Step 7: Run Your First Playbook

**Deploy user management (safe dry-run first):**
```bash
make users-check  # Preview changes
make users        # Apply changes
```

**Configure firewall (requires sudo password):**
```bash
make firewall-check  # Preview changes
make firewall        # Apply changes (will prompt for sudo password)
```

## OpenTofu Setup

OpenTofu provisions VMs on your Proxmox host.

### Step 1: Generate Proxmox API Token

Log into your Proxmox web interface:

1. Navigate to **Datacenter → Permissions → API Tokens**
2. Click **Add** to create a new token
3. Set:
   - **User**: `root@pam` (or your preferred admin user)
   - **Token ID**: `tofu-token` (or any name you prefer)
   - **Privilege Separation**: Uncheck for full permissions
4. **Save the token secret immediately** — you can't view it again

### Step 2: Configure Environment

```bash
cd tofu
cp .env.example .env
```

Edit `.env` with your Proxmox details:

```bash
PM_API_URL=https://10.10.15.18:8006/api2/json
PM_API_TOKEN_ID=root@pam!tofu-token
PM_API_TOKEN_SECRET=your-secret-here
PM_NODE_NAME=pve
PM_IMAGE_DATASTORE_ID=local
PM_VM_DATASTORE_ID=local-lvm
```

**Configuration guide:**
- `PM_API_URL`: Your Proxmox host URL (include `:8006/api2/json`)
- `PM_API_TOKEN_ID`: Format is `user@realm!tokenid`
- `PM_API_TOKEN_SECRET`: The secret from step 1
- `PM_NODE_NAME`: The Proxmox node name (visible in web UI)
- `PM_IMAGE_DATASTORE_ID`: Storage for ISO/cloud images (usually `local`)
- `PM_VM_DATASTORE_ID`: Storage for VM disks (usually `local-lvm`)

**Security**: The `.env` file is gitignored. Never commit it!

### Step 3: Build the OpenTofu Container

```bash
make build
```

### Step 4: Initialize OpenTofu

```bash
make init
```

This downloads the Proxmox provider and initializes the backend.

### Step 5: Plan Infrastructure Changes

```bash
make plan
```

Review the planned changes. On first run, this will show:
- Base images to be downloaded (Debian cloud images)
- Any VMs defined in `*.tf` files

### Step 6: Apply Infrastructure

```bash
make apply
```

Type `yes` when prompted. OpenTofu will:
1. Download base cloud images to Proxmox
2. Create any defined VMs

**Note**: The initial image download may take a few minutes depending on your connection.

### Step 7: Verify in Proxmox

Log into your Proxmox web interface and verify:
- Images appear in **Datacenter → <node> → local → ISO Images**
- VMs appear in the server list (if any are defined)

## Common Workflows

### Managing Firewall Configuration

The firewall role manages PF, DHCP, and DNS on OpenBSD firewalls:

```bash
cd ansible
make firewall-check  # Preview changes
make firewall        # Apply (requires sudo password)
```

See [OpenBSD Firewall Role docs](../ansible/roles/openbsd_firewall/README.md) for details.

### Managing WireGuard VPN

Configure WireGuard VPN servers (OpenBSD):

```bash
cd ansible
# First, manually create private key on the firewall (see WireGuard role docs)
make firewall  # Applies both wireguard_server and openbsd_firewall roles
```

See [WireGuard Server Role docs](../ansible/roles/wireguard_server/README.md) for key generation and client setup.

### Creating Proxmox VM Templates

Build cloud-init enabled VM templates:

```bash
cd ansible
make templates
```

This creates templates from cloud images downloaded by OpenTofu. See [PVE Templates docs](./pve-templates.md) for details.

### Managing VPS Configuration

Apply configuration to external VPS hosts:

```bash
cd ansible
make felix-check  # Preview changes for VPS hosts
make felix        # Apply changes
```

### Managing Synology NAS

Configure NFS shares on Synology NAS:

```bash
cd ansible
make nas-discover    # Gather current configuration
make nas-check       # Preview changes
make nas             # Apply changes
```

See [Synology NFS Role docs](../ansible/roles/synology_nfs/README.md) for details.

### Running Multiple Playbooks

Apply common configurations across all hosts:

```bash
cd ansible
make check-all  # Dry-run: users, firewall, and felix
make all        # Apply: users, firewall, and felix
```

**Warning**: Use `all` carefully — it applies changes to multiple hosts simultaneously.

### Ad-Hoc Commands

Run one-off commands on hosts:

```bash
cd ansible
make adhoc HOSTS=pve1 MODULE=shell ARGS='uptime'
make adhoc HOSTS=fw1 MODULE=raw ARGS='pfctl -sr'
```

Use `raw` module for OpenBSD hosts (no Python required).

## Troubleshooting

### Ansible Issues

**"Permission denied" or SSH connection failures:**
- Verify SSH key: `ssh -i keys/deploy/id_ed25519 deploy@<host-ip>`
- Check key permissions: `ls -l keys/deploy/id_ed25519` (should be 600)
- Ensure deploy user exists on target host
- Check `ansible.cfg` for correct `private_key_file` path

**"Privilege escalation failed":**
- Verify deploy user has sudo access: `ssh deploy@<host> sudo whoami`
- For OpenBSD, check `/etc/doas.conf` includes deploy user
- Run with `--ask-become-pass` if passwordless sudo isn't configured

**"Module not found" or collection errors:**
- Rebuild container: `make build`
- Install collections: `make galaxy`
- Check `requirements.yml` is present

**Container UID/GID issues:**
- Re-run `make init` to update `.env` with correct UID/GID
- Check `.env` file: `cat .env`

### OpenTofu Issues

**"Failed to query available provider packages":**
- Check internet connectivity
- Verify Docker can reach registry.opentofu.org
- Try: `make clean && make build && make init`

**"Error acquiring the state lock":**
- Another process is running OpenTofu
- Check for stuck processes: `docker compose ps`
- If truly stuck, manually remove `.terraform.tfstate.lock.info`

**Proxmox API connection failures:**
- Verify `.env` file exists and has correct values
- Test API access: `curl -k https://<proxmox-ip>:8006/api2/json/version`
- Check Proxmox API token is valid (may expire)
- Verify network access to Proxmox from your machine

**"Resource already exists" errors:**
- Check Proxmox web UI for existing resources with same IDs/names
- Review `terraform.tfstate` for drift
- Consider `make destroy` and re-apply (destructive!)

### Docker Issues

**"Cannot connect to Docker daemon":**
- Ensure Docker Desktop is running (macOS/Windows)
- Verify Docker service is active: `sudo systemctl status docker` (Linux)
- Check user permissions: `sudo usermod -aG docker $USER` (requires logout/login)

**"No space left on device":**
- Clean up Docker: `docker system prune -a`
- Check disk space: `df -h`
- Remove old images: `docker image prune -a`

### Network Issues

**Hosts are unreachable from containers:**
- Verify Docker network configuration
- Check firewall rules on your machine
- For VPN scenarios, ensure VPN is connected
- Test from container: `make sh` then `ping <host-ip>`

## Security Best Practices

### SSH Keys
- ✅ Generate unique keys per environment
- ✅ Use ed25519 keys (stronger than RSA)
- ✅ Set proper permissions (600 for private keys)
- ❌ Never commit private keys to git
- ❌ Never share private keys via insecure channels

### API Tokens
- ✅ Use API tokens instead of passwords
- ✅ Create tokens with minimum required privileges
- ✅ Rotate tokens regularly
- ❌ Never commit `.env` files
- ❌ Never use root password in automation

### Secrets Management
- Store sensitive values in `.env` files (gitignored)
- Consider using a password manager for key storage
- Document which secrets are required in `.env.example`
- Plan migration to proper secrets management (OpenBao, Vault) for production

### Firewall Rules
- Review firewall configurations before applying
- Use `--check` mode to preview changes
- Maintain documented network diagrams
- Test from multiple network locations

## Next Steps

### Learning More

- **Architecture**: Read [DNS Plan](./dns-plan.md) for network design
- **Templates**: See [PVE Templates](./pve-templates.md) for VM template creation
- **Roles**: Check individual role READMEs in `ansible/roles/*/README.md`
- **Make Commands**: Run `make help` in any directory for available targets

### Expanding Your Homelab

1. **Define your infrastructure**: Edit `tofu/*.tf` to add VMs
2. **Create VM templates**: Use `make ansible-templates` for cloud-init templates
3. **Add hosts to inventory**: Edit `ansible/inventories/hosts.yml`
4. **Configure hosts**: Use appropriate playbooks and roles
5. **Iterate**: Use `--check` mode frequently, make incremental changes

### Getting Help

- **Check role documentation**: Each role has a README with examples
- **Review existing configurations**: Look at templates and defaults
- **Use verbose mode**: Add `-vv` or `-vvv` to Ansible commands via `OPTS`
- **Test in isolation**: Use `LIMIT` to target single hosts

## Reference

### Key Files and Directories

```
homelab/
├── ansible/
│   ├── ansible.cfg              # Ansible configuration
│   ├── inventories/
│   │   ├── hosts.yml            # Inventory of managed hosts
│   │   ├── group_vars/          # Variables per group
│   │   └── host_vars/           # Variables per host
│   ├── keys/
│   │   └── deploy/              # SSH keys (gitignored)
│   ├── playbooks/               # Ansible playbooks
│   ├── roles/                   # Ansible roles
│   └── Makefile                 # Ansible commands
├── tofu/
│   ├── .env                     # OpenTofu secrets (gitignored)
│   ├── *.tf                     # Infrastructure definitions
│   └── Makefile                 # OpenTofu commands
├── docs/
│   ├── getting-started.md       # This file
│   ├── dns-plan.md             # DNS architecture
│   └── pve-templates.md        # VM template guide
└── Makefile                     # Root-level commands
```

### Important Make Targets

**Root level:**
- `make ansible-<target>` — Run Ansible target from root
- `make tofu-<target>` — Run OpenTofu target from root
- `make trufflehog` — Scan for secrets (security)

**Ansible:**
- `make init` — Initialize environment
- `make build` — Build Docker image
- `make ping` — Test connectivity
- `make users` — Manage users
- `make firewall` — Configure firewall
- `make templates` — Build VM templates
- `make all` — Run multiple playbooks

**OpenTofu:**
- `make build` — Build Docker image
- `make init` — Initialize OpenTofu
- `make plan` — Preview changes
- `make apply` — Apply changes
- `make shell` — Interactive shell

### Environment Variables

**Ansible (no .env file needed):**
- Configured via `ansible.cfg`
- Host-specific vars in inventory

**OpenTofu (.env file required):**
- `PM_API_URL` — Proxmox API endpoint
- `PM_API_TOKEN_ID` — API token identifier
- `PM_API_TOKEN_SECRET` — API token secret
- `PM_NODE_NAME` — Proxmox node name
- `PM_IMAGE_DATASTORE_ID` — Image storage
- `PM_VM_DATASTORE_ID` — VM disk storage

See `.env.example` files for full details.
