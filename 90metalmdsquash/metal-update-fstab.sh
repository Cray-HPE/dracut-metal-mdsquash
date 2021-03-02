#!/bin/sh
set -x

fstab_metal='fstab.metal'
fstab_metal_new=/etc/$fstab_metal
fstab_metal_old=/sysroot/etc/$fstab_metal

if [ -f "$fstab_metal_old" ]; then
    mount -a -T "$fstab_metal_old"
else
    cp -v "$fstab_metal_new" "$fstab_metal_old"
fi
