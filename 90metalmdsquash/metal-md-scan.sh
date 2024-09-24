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
# metal-md-scan.sh
[ "${METAL_DEBUG:-0}" = 0 ] || set -x

# Wait for disks to exist.
command -v disks_exist > /dev/null 2>&1 || . /lib/metal-lib.sh
disks_exist || exit 1

# On a reboot this will load the raid module before assembling any available RAIDs.
# On a deployment this will do nothing.
# NOTE: it does not matter which raid method is active on the array (stripe/mirror), raid1 will load the necessary dependencies
# for mdadm to take over.
if ! lsmod | grep -q raid1; then
  :
  modprobe raid1 || metal_die 'no raid module available (lsmod | grep raid)!'
  mdraid_start > /dev/null 2>&1 # Force RAID start.
  mdadm --assemble --scan > /dev/null
  _trip_udev
  # FIXME: both $SQFS_DRIVE_SCHEME and $SQFS_DRIVE_AUTHORITY are available when this runs but they should be better acknowledged/defined in this script context.
  [ -f "/dev/disk/by-${SQFS_DRIVE_SCHEME,,}/${SQFS_DRIVE_AUTHORITY^^:-}" ] && echo 2 > /tmp/metalsqfsdisk.done
  # We can't check for the squashFS image without mounting, but if we have these items we should
  # assume that this is a disk boot already loaded with artifacts or this is a network boot
  # that's about to obtain artifacts into an existing array (/sbin/metal-md-disks.sh).
  # We also can't check for the oval image for the same reason.
else
  # If the raid module is loaded then give it a bump so any code in this file can anticipate RAID
  # RAID arrays to be available if they exist.
  mdadm --assemble --scan
  _trip_udev
fi

# Also check for any RAIDs that may be in PENDING, sometimes the RAID arrays may stall the boot
# if they did not fully sync before rebooting. The stall is usually only 1-5minutes, but it may vary
# to an hour or indefinite.
if [ -d /dev/md ]; then
  while IFS= read -r -d '' md; do
    handle=$(echo -n "$md" | cut -d '/' -f3)
    if grep -A 2 "$handle" /proc/mdstat | grep -qi pending; then
      mdadm --readwrite "$md"
    fi
  done < <(find /dev/md** -type b -print0)
fi
