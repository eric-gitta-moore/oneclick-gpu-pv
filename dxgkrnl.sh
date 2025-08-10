#!/bin/bash -e
BRANCH=linux-msft-wsl-6.6.y

if [ "$EUID" -ne 0 ]; then
    echo "Switching to root..."
    exec sudo $0 "$@"
fi

apt update
apt install -y git dkms

git clone -b $BRANCH --depth=1 https://github.com/microsoft/WSL2-Linux-Kernel
cd WSL2-Linux-Kernel
VERSION=$(git rev-parse --short HEAD)

cp -r drivers/hv/dxgkrnl /usr/src/dxgkrnl-$VERSION
mkdir -p /usr/src/dxgkrnl-$VERSION/inc/{uapi/misc,linux}
cp include/uapi/misc/d3dkmthk.h /usr/src/dxgkrnl-$VERSION/inc/uapi/misc/d3dkmthk.h
cp include/linux/hyperv.h /usr/src/dxgkrnl-$VERSION/inc/linux/hyperv_dxgkrnl.h
sed -i 's/\$(CONFIG_DXGKRNL)/m/' /usr/src/dxgkrnl-$VERSION/Makefile
sed -i 's#linux/hyperv.h#linux/hyperv_dxgkrnl.h#' /usr/src/dxgkrnl-$VERSION/dxgmodule.c
echo "EXTRA_CFLAGS=-I\$(PWD)/inc" >> /usr/src/dxgkrnl-$VERSION/Makefile

# make -j10 KERNELRELEASE=`uname -r` -C /lib/modules/`uname -r`/build M=/var/lib/dkms/dxgkrnl/$VERSION/build
# if 6.8 kernel
sed -i 's#eventfd_signal(event->cpu_event, 1);#eventfd_signal(event->cpu_event);#' /usr/src/dxgkrnl-$VERSION/dxgmodule.c
# if 6.12 kernal
sed -i '1i#include <linux/vmalloc.h>' /usr/src/dxgkrnl-$VERSION/dxgvmbus.c
sed -i '1i#include <linux/vmalloc.h>' /usr/src/dxgkrnl-$VERSION/hmgr.c
sed -i '1i#include <linux/vmalloc.h>' /usr/src/dxgkrnl-$VERSION/dxgadapter.c
sed -i '1i#include <linux/vmalloc.h>' /usr/src/dxgkrnl-$VERSION/ioctl.c


cat > /usr/src/dxgkrnl-$VERSION/dkms.conf <<EOF
PACKAGE_NAME="dxgkrnl"
PACKAGE_VERSION="$VERSION"
BUILT_MODULE_NAME="dxgkrnl"
DEST_MODULE_LOCATION="/kernel/drivers/hv/dxgkrnl/"
AUTOINSTALL="yes"
EOF

# dkms add dxgkrnl/$VERSION
dkms build dxgkrnl/$VERSION
dkms install dxgkrnl/$VERSION
# modprobe dxgkrnl
# modprobe vgem

# check
lsmod | grep dxgkrnl
echo "DONE"

