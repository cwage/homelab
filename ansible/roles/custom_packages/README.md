# Custom Packages Role

Manages installation of custom-built or third-party packages that aren't available in standard APT repositories.

## Purpose

This role handles deployment of locally-built or downloaded package files (`.deb`) to managed hosts. Currently supports TinyFugue (a MUD client), but can be extended for other custom packages.

## Requirements

- **Target OS**: Debian/Ubuntu Linux (uses APT/dpkg)
- **Privileges**: Requires `become: true` (sudo/root access)
- **Build artifacts**: Package `.deb` files must be built before deployment
- **Python**: Python 3 on target hosts

## Role Variables

### Default Variables

Defined in `defaults/main.yml`:

```yaml
# TinyFugue package configuration
tinyfugue_deb_filename: tinyfugue_5.0-widechar-2_amd64.deb
tinyfugue_deb_local_path: "{{ role_path }}/../../files/packages/{{ tinyfugue_deb_filename }}"
tinyfugue_deb_remote_path: "/tmp/{{ tinyfugue_deb_filename }}"
```

### Variable Details

- `tinyfugue_deb_filename`: Name of the built package file
- `tinyfugue_deb_local_path`: Local path where package is stored (relative to role)
- `tinyfugue_deb_remote_path`: Temporary location on target host for installation

## Dependencies

None. This is a standalone role, but packages must be pre-built.

## Building Packages

### TinyFugue

Build the TinyFugue package before deploying:

```bash
# From ansible directory
make build-tinyfugue
```

This creates `ansible/files/packages/tinyfugue_5.0-widechar-2_amd64.deb`.

**Build process:**
- Uses Docker container with build environment
- Compiles TinyFugue from source with widechar support
- Packages as `.deb` file
- Static binary with no external dependencies

## Example Usage

### Basic Playbook

```yaml
---
- name: Install custom packages
  hosts: linode_vps
  become: true
  roles:
    - custom_packages
```

### Running the Role

```bash
# First, build the package
cd ansible
make build-tinyfugue

# Then deploy via playbook
ansible-playbook playbooks/vps.yml -vv
```

### Check Mode Support

The role skips package operations in check mode but still validates the local package exists:

```bash
ansible-playbook playbooks/vps.yml --check --diff
```

## What This Role Does

### 1. Validate Local Package

- Checks if `.deb` package exists on Ansible control machine
- Uses `delegate_to: localhost` to check locally
- Runs once, not per host
- **Fails playbook if package is missing**

### 2. Copy Package to Target

- Uploads `.deb` file to `/tmp/` on target host
- Sets file permissions to 0644
- Skipped in check mode

### 3. Install Package

- Installs package using `apt` module with `deb:` parameter
- Uses `dpkg -i` under the hood
- No dependency resolution (package should be self-contained)
- Skipped in check mode

### 4. Cleanup

- Removes temporary `.deb` file from `/tmp/`
- Keeps target filesystem clean
- Skipped in check mode

## Outputs

After running this role:
- TinyFugue (or other custom packages) is installed
- Package is registered with dpkg
- Can be removed with: `apt remove tinyfugue`
- Temporary files are cleaned up

## Assumptions and Limitations

### Assumptions
- Packages are built before deployment (role doesn't build them)
- Packages are self-contained (no dependencies) or dependencies are already installed
- Target architecture matches built package (amd64)
- Sufficient disk space in `/tmp/` for package file

### Limitations
- Only handles `.deb` packages (Debian/Ubuntu)
- No version checking (always installs/overwrites)
- No dependency resolution (unlike apt repositories)
- Single package per role invocation

### Design Decisions

**Why local build vs. repository?**
- Custom builds with specific flags (e.g., widechar support)
- No suitable packages in standard repos
- Full control over build environment
- Reproducible builds via Docker

**Why not include .deb in git?**
- Binary files bloat git history
- Packages should be built from source
- Can be rebuilt consistently via Makefile
- Keeps repository size manageable

## Integration with Other Roles

Typical role order:
1. **Packages role**: Install system packages
2. **Custom packages role**: Install custom-built packages
3. **Application roles**: Configure services

## Adding New Custom Packages

### Step 1: Create Build Script

Add to `ansible/files/build-<package>.sh`:

```bash
#!/bin/bash
set -e

# Download source
wget https://example.com/package.tar.gz
tar xzf package.tar.gz
cd package

# Build
./configure --prefix=/usr
make

# Package
mkdir -p package/DEBIAN
cat > package/DEBIAN/control << EOF
Package: mypackage
Version: 1.0
Architecture: amd64
Maintainer: Your Name
Description: My custom package
EOF

make install DESTDIR=package
dpkg-deb --build package mypackage_1.0_amd64.deb
```

### Step 2: Add Dockerfile

Create `ansible/Dockerfile.mypackage-builder`:

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
```

### Step 3: Add to docker-compose.yml

```yaml
services:
  mypackage-builder:
    build:
      context: .
      dockerfile: Dockerfile.mypackage-builder
    volumes:
      - ./files:/files:z
```

### Step 4: Add Makefile Target

In `ansible/Makefile`:

```makefile
build-mypackage: ## Build mypackage .deb
	$(DC) build mypackage-builder
	$(DC) run --rm mypackage-builder bash /files/build-mypackage.sh
```

### Step 5: Update Role Variables

In role defaults or inventory:

```yaml
mypackage_deb_filename: mypackage_1.0_amd64.deb
mypackage_deb_local_path: "{{ role_path }}/../../files/packages/{{ mypackage_deb_filename }}"
mypackage_deb_remote_path: "/tmp/{{ mypackage_deb_filename }}"
```

### Step 6: Add Tasks

Add tasks similar to TinyFugue deployment.

## Common Issues

**"Package missing" error:**
- Build package first: `make build-tinyfugue`
- Check file exists: `ls ansible/files/packages/`
- Verify path in defaults matches actual location

**Package installation fails:**
- Check architecture matches: `dpkg --print-architecture`
- Verify package isn't corrupted: `dpkg-deb -I <package>.deb`
- Check for dependency issues: `dpkg -i <package>.deb` (will show missing deps)

**Permission denied during copy:**
- Ensure become: true in playbook
- Check `/tmp/` is writable
- Verify file permissions on local package

**Package already installed but outdated:**
- Remove first: `apt remove <package>`
- Or use package version in filename for tracking

## Testing

```bash
# Build package
make build-tinyfugue

# Verify package built
ls -lh files/packages/tinyfugue*.deb

# Check package contents
dpkg-deb -c files/packages/tinyfugue*.deb

# Deploy with check mode (validates package exists)
ansible-playbook playbooks/vps.yml --check

# Deploy for real
ansible-playbook playbooks/vps.yml

# Verify installation on target
ansible linode_vps -m shell -a "dpkg -l | grep tinyfugue"
ansible linode_vps -m shell -a "which tf"
```

## Related Documentation

- [Getting Started Guide](../../../docs/getting-started.md) — Initial setup
- [Packages Role](../packages/README.md) — Standard package installation
- [TinyFugue Homepage](http://tinyfugue.sourceforge.net/) — About TinyFugue
