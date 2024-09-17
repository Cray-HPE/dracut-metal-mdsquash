#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022-2024 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#
# parse-metal.sh

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
getargbool 0 metal.debug -d -y METAL_DEBUG && METAL_DEBUG=1
[ "${METAL_DEBUG:-0}" = 0 ] || set -x

METAL_DISKS=$(getargnum 2 1 10 metal.disks)
getargbool 0 metal.no-wipe -d -y METAL_NOWIPE && METAL_NOWIPE=1 || METAL_NOWIPE=0
METAL_OVERLAY=$(getarg rd.live.overlay)
[ -z "${METAL_OVERLAY}" ] && METAL_OVERLAY=LABEL=ROOTRAID
METAL_SERVER=$(getarg metal.server=)

# For ${:+} BASH substitution to work, the value must be null or unset (0 != null in BASH)
getargbool 0 metal.ipv4 -d -y METAL_IPV4 && METAL_IPV4=1
[ "${METAL_IPV4}" = 0 ] && METAL_IPV4=''

export METAL_DEBUG
export METAL_DISKS
export METAL_NOWIPE
export METAL_OVERLAY
export METAL_SERVER
export METAL_IPV4

metal_minimum_disk_size=$(getargnum 16 0 1000000000 metal.min-disk-size)
# convert Gigabytes to bytes
METAL_IGNORE_THRESHOLD=$((metal_minimum_disk_size * 1024 ** 3))
export METAL_IGNORE_THRESHOLD

# root must never be empty; if it is then nothing will boot - dracut will never find anything todo.
root=$(getarg root)
case "$root" in
  live:/dev/*)
    sqfs_drive_url=${root///dev\/disk\/by-}
    sqfs_drive_spec=${sqfs_drive_url#*:}
    SQFS_DRIVE_SCHEME=${sqfs_drive_spec%%/*}
    SQFS_DRIVE_AUTHORITY=${sqfs_drive_spec#*/}
    ;;
  live:*)
    sqfs_drive_url=${root#live:}
    sqfs_drive_spec=${sqfs_drive_url#*:}
    SQFS_DRIVE_SCHEME=${sqfs_drive_spec%%=*}
    SQFS_DRIVE_AUTHORITY=${sqfs_drive_spec#*=}
    ;;
  '')
    warn "No root; root needed - the system will likely fail to boot."
    # do not fail, allow dracut to handle everything in case an operator/admin is doing something.
    ;;
  kdump)
    :
    ;;
  *)
    warn "alien root! unrecognized root= parameter: root=${root}"
    ;;
esac

export SQFS_DRIVE_SCHEME
export SQFS_DRIVE_AUTHORITY
