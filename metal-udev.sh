#!/bin/sh
# metal-udev.sh ; copies all new udev rules into the overlayFS

type metal_die >/dev/null 2>&1 || . /lib/metal-md-lib.sh

made=/etc/udev/rules.d/
live=/run/initramfs/overlayfs/${live_dir}/$(_overlayFS_path_spec)/etc/udev/rules.d

ls -l $live
mkdir -pv $live
cp -pv $made* $live/ || metal_die 'FATAL: udev rules did not provision from dracut!! Beware of udev problems.'
ls -l $live
