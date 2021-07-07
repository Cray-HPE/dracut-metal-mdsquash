#!/bin/sh
set -x

fstab_metal='fstab.metal'
fstab_metal_new=/etc/$fstab_metal
fstab_metal_old=/sysroot/etc/$fstab_metal

if [ -f "$fstab_metal_old" ]; then
    mkdir -pv "$(mount -a -f -v -T /etc/fstab.metal | awk '{print $1}' | tr -s '\n' ' ')"
    mount -a -v -T "$fstab_metal_old"
else
    [ -f "$fstab_metal_new" ] && cp -v "$fstab_metal_new" "$fstab_metal_old"
fi
