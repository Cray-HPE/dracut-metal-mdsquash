#!/bin/sh
# Copyright 2021 Hewlett Packard Enterprise Development LP
# metal-md-disks.sh for metalmdsquash

# DEVICES EXIST or DIE
ls /dev/sd* > /dev/null 2>&1 || exit 1

# PRELIMINARY SCAN
type metal_die > /dev/null 2>&1 || . /lib/metal-md-lib.sh
/sbin/metal-md-scan
[ -z "${metal_server:-}" ] && exit 0

# DISKS or RETRY
md_disks="$(lsblk -l -o SIZE,NAME,TYPE,TRAN | grep -E '(sata|nvme|sas)' | sort -h | awk '{print $2}' | head -n ${metal_disks} | tr '\n' ' ')"
[ -z "${md_disks}" ] && exit 1

# PAVE & GO-AROUND/RETRY
[ ! -f /tmp/metalpave.done ] && [ "${metal_nowipe:-0}" != 1 ] && pave

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
