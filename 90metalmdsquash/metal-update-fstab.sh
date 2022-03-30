#!/bin/bash
set -x
type metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

fstab_metal_new=$metal_fstab
fstab_metal_old=/sysroot$metal_fstab

if [ -f "$fstab_metal_old" ]; then
    mkdir -pv "$(mount -a -f -v -T $fstab_metal_new | awk '{print $1}' | tr -s '\n' ' ')"
    mount -a -v -T "$fstab_metal_old"
else
    # If a new FSTab exists, this copies it regardless if there is no diff.
    [ -f "$fstab_metal_new" ] && cp -v "$fstab_metal_new" "$fstab_metal_old"
fi
