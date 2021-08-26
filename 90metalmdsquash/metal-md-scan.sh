#!/bin/sh
# Copyright 2021 Hewlett Packard Enterprise Development LP
# metal-md-scan.sh for metalmdsquash

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
else
    # If the raid module is loaded then give it a bump so any code in this file can anticipate RAID
    # RAID arrays to be available if they exist.
    mdadm --assemble --scan
    udevadm settle 2>/dev/null
fi

# Also check for any RAIDs that may be in PENDING, sometimes the RAID arrays may stall the boot
# if they did not fully sync before rebooting. The stall is usually only 1-5minutes, but it may vary
# to an hour or indefinite.
for md in $(find /dev/md** -type b); do
    handle=$(echo -n $md | cut -d '/' -f3)
    if grep -B 2 $handle /proc/mdstat | grep -qi pending ; then
        mdadm --readwrite $md
    fi
done