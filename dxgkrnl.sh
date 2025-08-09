#!/bin/bash -e
BRANCH=linux-msft-wsl-6.6.y

if [ "$EUID" -ne 0 ]; then
    echo "Swithing to root..."
    exec sudo $0 "$@"
fi

apt-get install -y git dkms

git clone -b $BRANCH --depth=1 https://github.com/microsoft/WSL2-Linux-Kernel
cd WSL2-Linux-Kernel
VERSION=$(git rev-parse --short HEAD)

cp -r drivers/hv/dxgkrnl /usr/src/dxgkrnl-$VERSION

cat > /usr/src/dxgkrnl-$VERSION/dkms.conf <<EOF
PACKAGE_NAME="dxgkrnl"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME="dxgkrnl"
DEST_MODULE_LOCATION="/kernel/drivers/hv/dxgkrnl/"
AUTOINSTALL="yes"
EOF

dkms add dxgkrnl/$VERSION
dkms build dxgkrnl/$VERSION
dkms install dxgkrnl/$VERSION
modprobe dxgkrnl


add-apt-repository ppa:kisak/kisak-mesa
apt install -y mesa-utils

echo "export LIBVA_DRIVER_NAME=d3d12" > /etc/profile.d/d3d.sh
echo "export MESA_LOADER_DRIVER_OVERRIDE=vgem" >> /etc/profile.d/d3d.sh

echo "DONE"