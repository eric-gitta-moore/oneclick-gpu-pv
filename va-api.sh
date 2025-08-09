#!/bin/bash -e
add-apt-repository ppa:kisak/kisak-mesa
apt install -y mesa-utils

# if ls: cannot access '/dev/dri/card0': No such file or directory
modprobe vgem

echo "export LIBVA_DRIVER_NAME=d3d12" > /etc/profile.d/d3d.sh
echo "export MESA_LOADER_DRIVER_OVERRIDE=vgem" >> /etc/profile.d/d3d.sh
echo "export GST_VAAPI_DRM_DEVICE=/dev/dri/card0" >> /etc/profile.d/d3d.sh

echo "DONE"
