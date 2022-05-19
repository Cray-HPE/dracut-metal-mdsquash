#!/bin/bash
# Copyright 2021 Hewlett Packard Enterprise Development LP
# metal-md-disks.sh for metalmdsquash

# DEVICES EXIST or DIE
ls /dev/sd* > /dev/null 2>&1 || exit 1

# If disks exist then it's worthwhile to load libraries.
type metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh
type pave > /dev/null 2>&1 || . /lib/metal-md-lib.sh

# PRELIMINARY SCAN; this jumpstarts any existing RAIDs on regular "non-deployment boots." 
# EXIT 0 if no metal-server is set; exit nicely after the preliminary RAID scan, this is a "non-deployment boot"
/sbin/metal-md-scan
[ -z "${metal_server:-}" ] && exit 0

# PAVE & GO-AROUND/RETRY
[ ! -f /tmp/metalpave.done ] && [ "${metal_nowipe:-0}" != 1 ] && pave

# DISKS; disks were detected, find the amount we need or die. Also die if there are 0 disks.
if [ ! -f /tmp/metalsqfsdisk.done ]; then
    md_disks=()
    for disk in $(seq 1 $metal_disks); do
        md_disk=$(metal_resolve_disk $(metal_scand $disk) $metal_disk_small)
        md_disks+=( $md_disk )
    done
    if [ ${#md_disks[@]} = 0 ]; then
        metal_die "No disks were found for the OS that were [$metal_disk_small] (in bytes) or smaller!"
        exit 1
    else
        warn "Found the following disks for the main RAID array (qty. [$metal_disks]): [${md_disks[@]}]"
    fi
fi

# Verify structure ...
[ ! -f /tmp/metalsqfsdisk.done ] && make_raid_store
[ ! -f /tmp/metalovalimg.done ] && add_overlayfs
[ ! -f /tmp/metalsqfsimg.done ] && add_sqfs

# EXIT or RETRY
if [ -n "${metal_overlay:-}" ]; then
    [ -f /tmp/metalsqfsdisk.done ] && [ -f /tmp/metalsqfsimg.done ] && [ -f /tmp/metalovalimg.done ] && exit 0
else
    [ -f /tmp/metalsqfsdisk.done ] && [ -f /tmp/metalsqfsimg.done ] && exit 0
fi
