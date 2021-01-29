#!/bin/sh

if ! lsmod | grep -q raid1 ; then :
    modprobe raid1 || metal_die 'no raid module!'
    mdraid_start # Force RAID start.
    mdadm --assemble --scan
    udevadm settle 2>/dev/null
    [ -f "/dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority^^}" ] && echo 2 > /tmp/metalsqfsdisk.done
    # We can't check for the squashFS image without mounting, but if we have these items we should
    # assume that this is a disk boot already loaded with artifacts or this is a network boot
    # that's about to obtain artifacts into an existing array (/sbin/metal-md-disks.sh).
    # We also can't check for the oval image for the same reason.
fi