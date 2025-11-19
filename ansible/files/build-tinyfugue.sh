#!/bin/bash
set -e

echo "Building TinyFugue (widechar branch)..."

# Clone the repository
if [ ! -d "tinyfugue" ]; then
    echo "Cloning tinyfugue repository..."
    git clone https://github.com/kruton/tinyfugue.git
fi

cd tinyfugue

# Checkout the widechar branch
echo "Checking out widechar branch..."
git checkout widechar
git pull origin widechar

# Configure and build with static linking
echo "Running configure..."
# Use absolute paths to force static linking of specific libraries
export LDFLAGS="-static-libgcc -static-libstdc++"
export LIBS="/usr/lib/x86_64-linux-gnu/libicui18n.a /usr/lib/x86_64-linux-gnu/libicuuc.a /usr/lib/x86_64-linux-gnu/libicudata.a /usr/lib/x86_64-linux-gnu/libpcre.a /usr/lib/x86_64-linux-gnu/libz.a -lstdc++ -lm -lpthread -ldl"
./configure --prefix=/usr

echo "Building with static linking..."
make clean
make all

# Create debian package manually using dpkg-deb
echo "Creating debian package structure..."
PKG_DIR="tinyfugue-package"
mkdir -p "${PKG_DIR}/usr/bin"
mkdir -p "${PKG_DIR}/usr/share/tf-lib"
mkdir -p "${PKG_DIR}/DEBIAN"

# Copy files
cp src/tf "${PKG_DIR}/usr/bin/tf"
chmod 755 "${PKG_DIR}/usr/bin/tf"
cp -r tf-lib/* "${PKG_DIR}/usr/share/tf-lib/"
chmod -R 755 "${PKG_DIR}/usr/share/tf-lib"

# Create control file
cat > "${PKG_DIR}/DEBIAN/control" << 'CONTROL_EOF'
Package: tinyfugue
Version: 5.0-widechar-2
Section: games
Priority: optional
Architecture: amd64
Maintainer: homelab-ansible
Description: TinyFugue MUD client with wide character support (static build)
 TinyFugue (aka "tf") is a flexible, screen-oriented MUD client.
 This build includes wide character (Unicode) support and is statically
 linked for maximum portability.
CONTROL_EOF

# Build the .deb package
echo "Building .deb package..."
dpkg-deb --build "${PKG_DIR}" tinyfugue_5.0-widechar-2_amd64.deb

# Move the .deb to the output directory
echo "Moving package to /output..."
mv tinyfugue_5.0-widechar-2_amd64.deb /output/

echo "Build complete! Package available in files/packages/"
ls -lh /output/*.deb
