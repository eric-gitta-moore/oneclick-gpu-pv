#!/bin/bash -e

# Bionic (18.04), Focal (20.04), Jammy (22.04) - Discontinued - Long term users can use kisak-mesa stable
# https://launchpad.net/~kisak/+archive/ubuntu/turtle
add-apt-repository ppa:kisak/turtle

apt install -y mesa-utils

# if ls: cannot access '/dev/dri/card0': No such file or directory
# modprobe vgem

apt install mesa-va-drivers vainfo
echo "export LIBVA_DRIVER_NAME=d3d12" > /etc/profile.d/d3d.sh
echo "export MESA_LOADER_DRIVER_OVERRIDE=vgem" >> /etc/profile.d/d3d.sh
echo "export GST_VAAPI_DRM_DEVICE=/dev/dri/card0" >> /etc/profile.d/d3d.sh

echo "DONE"
