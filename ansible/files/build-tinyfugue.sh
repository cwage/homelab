#!/bin/bash
set -e

echo "Building TinyFugue (main branch)..."

# Clone the repository
if [ ! -d "tinyfugue" ]; then
    echo "Cloning tinyfugue repository..."
    git clone https://github.com/kruton/tinyfugue.git
fi

cd tinyfugue

# Checkout the main branch
echo "Checking out main branch..."
git checkout main
git pull origin main

# Configure with CMake. Upstream migrated from autotools to CMake (and from
# PCRE to PCRE2). Features are auto-detected from the build deps installed in
# the builder image: TLS (OpenSSL), wide-character (ICU), MCCP (zlib), PCRE2.
echo "Running CMake configure..."
# CMAKE_INSTALL_PREFIX must be /usr (not the default /usr/local): the runtime
# library directory (TFLIBDIR, e.g. /usr/share/tf-lib) is baked into the binary
# at configure time from this prefix. Files are staged via DESTDIR below.
cmake -S . -B build -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr

echo "Building..."
cmake --build build -j"$(nproc)"

# Stage the install into the package tree. cmake installs the binary to
# usr/bin/tf and the runtime library to usr/share/tf-lib, matching the layout
# the package has always shipped.
echo "Staging install..."
PKG_DIR="tinyfugue-package"
rm -rf "${PKG_DIR}"
mkdir -p "${PKG_DIR}/DEBIAN"
DESTDIR="$(pwd)/${PKG_DIR}" cmake --install build

# Strip the binary to shrink the package.
strip "${PKG_DIR}/usr/bin/tf" || true

# This is a dynamically-linked build (the old autotools static-link hack does
# not carry over to CMake). The builder image base matches the target host's
# Ubuntu release, so the shared-library sonames line up. Derive the runtime
# Depends from the binary with dpkg-shlibdeps so apt installs the right libs.
echo "Computing runtime dependencies..."
mkdir -p debian
printf 'Source: tinyfugue\nMaintainer: homelab-ansible\n\nPackage: tinyfugue\nArchitecture: amd64\nDescription: placeholder\n' > debian/control
DEPENDS="$(dpkg-shlibdeps -O "${PKG_DIR}/usr/bin/tf" 2>/dev/null | sed 's/^shlibs:Depends=//')"
echo "Depends: ${DEPENDS}"

# Create control file
cat > "${PKG_DIR}/DEBIAN/control" << CONTROL_EOF
Package: tinyfugue
Version: 1:5.0-main-2
Section: games
Priority: optional
Architecture: amd64
Maintainer: homelab-ansible
Depends: ${DEPENDS}
Description: TinyFugue MUD client (CMake build from upstream main)
 TinyFugue (aka "tf") is a flexible, screen-oriented MUD client.
 Built from the upstream main branch with wide-character (ICU),
 TLS (OpenSSL), MCCP compression (zlib), and PCRE2 support.
CONTROL_EOF

# Build the .deb package
echo "Building .deb package..."
dpkg-deb --build "${PKG_DIR}" tinyfugue_5.0-main-2_amd64.deb

# Move the .deb to the output directory
echo "Moving package to /output..."
mv tinyfugue_5.0-main-2_amd64.deb /output/

echo "Build complete! Package available in files/packages/"
ls -lh /output/*.deb
