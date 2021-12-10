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
# MAINTAINER NOTE: We filter out NVME partitions because they'll exist at this point since pave() is called afterwards.
# MAINTAINER NOTE: Regardless of gcp mode, this will ignore any NVME partition incase they stick around after wiping.
md_disks="$(lsblk -l -o SIZE,NAME,TYPE,TRAN | grep -E '('"$metal_transports"')' | sort -h | grep -vE 'p[0-9]+$' | awk '{print $2}' | head -n ${metal_disks} | tr '\n' ' ' | sed 's/ *$//')"
[ -z "${md_disks}" ] && exit 1

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
