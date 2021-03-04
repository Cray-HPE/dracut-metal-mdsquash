#!/bin/sh
# metal-udev.sh ; copies all new udev rules into the overlayFS

made=/etc/udev/rules.d/
live=/sysroot/etc/udev/rules.d

ls -l $live
cp -pv $made* $live/
ls -l $live
