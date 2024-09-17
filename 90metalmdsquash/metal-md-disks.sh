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
# metal-md-disks.sh
[ "${metal_debug:-0}" = 0 ] || set -x

# This module already ran if /dev/metal exists..
[ -L /dev/metal ] && exit 0

# Wait for disks to exist.
command -v disks_exist > /dev/null 2>&1 || . /lib/metal-lib.sh
disks_exist || exit 1

# Remove the label associated with the SQFS RAID if it exists to ensure dmsquash-live waits.
# This would only exist on a reboot.
[ -b /dev/md/SQFS ] && xfs_admin -L -- /dev/md/SQFS

# Now that disks exist it's worthwhile to load the libraries.
command -v pave > /dev/null 2>&1 || . /lib/metal-md-lib.sh

# Check for existing RAIDs
/sbin/metal-md-scan

# Wipe; this returns early if a wipe was already done.
pave

# At this point this module is required; a disk must be created or the system has nothing to boot.
# Die if no viable disks are found; otherwise continue to disk creation functions.
if [ ! -f /tmp/metalsqfsdisk.done ] && [ "${metal_nowipe}" -eq 0 ]; then
  md_disks=()
  disks="$(metal_scand)"
  IFS=" " read -r -a pool <<< "$disks"
  for disk in "${pool[@]}"; do
    if [ "${#md_disks[@]}" -eq "${metal_disks}" ]; then
      break
    fi
    md_disk=$(metal_resolve_disk "$disk" "$metal_disk_small")
    if [ -n "${md_disk}" ]; then
      md_disks+=("$md_disk")
    fi
  done

  if [ "${#md_disks[@]}" -lt "$metal_disks" ]; then
    metal_die "No disks were found for the OS that were [$metal_disk_small] (in bytes) or larger, all were too small or had filesystems present!"
    exit 1
  else
    echo >&2 "Found the following disk(s) for the main RAID array (qty. [$metal_disks]): [${md_disks[*]}]"
  fi
fi

# Create disks.
[ ! -f /tmp/metalsqfsdisk.done ] && make_raid_store "${md_disks[@]}"
[ ! -f /tmp/metalovaldisk.done ] && make_raid_overlay "${md_disks[@]}"
[ ! -f /tmp/metalovalimg.done ] && add_overlayfs
[ ! -f /tmp/metalsqfsimg.done ] && add_sqfs

# Verify our disks were created; satisfy the wait_for_dev hook if they were, otherwise keep waiting.
if [ -f /tmp/metalsqfsdisk.done ] && [ -f /tmp/metalsqfsimg.done ]; then
  if [ -n "${metal_overlay:-}" ] && [ ! -f /tmp/metalovalimg.done ]; then
    # Waiting on overlay creation.
    exit 1
  fi
  if metal_md_exit; then
    # This module has finished; this initqueue script needs to exit cleanly.
    exit 0
  else
    # This module had issues trying to exit.
    metal_die "Failed to setup root dependencies."
  fi
fi
