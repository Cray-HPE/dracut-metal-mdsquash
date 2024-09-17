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
# metal-lib.sh
#
# NOTES:
# This provides functions to:
# - https://github.com/Cray-HPE/dracut-metal-mdsquash
# - https://github.com/Cray-HPE/dracut-metal-dmk8s
# - https://github.com/Cray-HPE/dracut-metal-luksetcd
#
# MAINTAINER NOTE: these functions should not be complicated!
# - constant       : A constant used throughout this module and dependent modules.
# - core function  : A function that must not fail to execute when this library loads.
# - function       : A function that can be used by any dracut module sourcing this library.
[ "${METAL_DEBUG:-0}" = 0 ] || set -x

##############################################################################
# core function: _load_dracut_dep
#
# Load the dracut library dependency; certain functions of the native library are used
# throughout this codebase. This must load or this library should fail to load.
#
# NOTE: This library exists at /lib/dracut-lib.sh when one is inside the initrd context.
#       During runtime (inside the Linux context) the lib will exist
#       at /usr/lib/dracut/modules.d/99base/dracut-lib.sh
#
# - rd_lib is the library location inside of an initrd.
# - rt_lib is the library location during runtime.
_load_dracut_dep() {
  local rd_lib=/lib/dracut-lib.sh
  local rt_lib=/usr/lib/dracut/modules.d/99base/dracut-lib.sh
  if [ -e $rd_lib ]; then
    lib=${rd_lib}
  elif [ -e ${rt_lib} ]; then
    lib=${rt_lib}
  else
    cat >&2 << EOF
FATAL ERROR: Neither dracut-lib.sh location exists. Dracut is possibly not installed, or has changed locations:
- $rt_lib
- $rd_lib

The metal-lib.sh library can not load in this state.
EOF
    return 1
  fi
  command -v die > /dev/null 2>&1 || . $lib
}
_load_dracut_dep

##############################################################################
# constant: METAL_DONE_FILE_PAVED
#
# Log directory.
export METAL_LOG_DIR="${METAL_LOG_DIR:-/var/log/metal}"
mkdir -p "$METAL_LOG_DIR"

##############################################################################
# constant: METAL_HASH
# constant: METAL_DOCS_URL
#
# This is the VCS hash for commit that produced this library, it is auto-filled
# when this module is built into an OS package.
# This is useful for printing URLs to documentation that are relevant to the
# library running in an initramFS.
METAL_HASH='@@metal-hash@@'
if [[ ${METAL_HASH} =~ 'metal-hash' ]]; then
  # Default to main if this is running directly out of the repo.
  METAL_HASH='main'
fi
export METAL_HASH
export METAL_DOCS_URL="https://github.com/Cray-HPE/dracut-metal-mdsquash/tree/${METAL_HASH}"

##############################################################################
# constant: METAL_DONE_FILE_PAVED
#
# This file path present a file that the wipe function creates when it is
# invoked. The existence of the file implies the wipe code as been invoked,
# the contents of the file can be interpretted to determine what the wipe
# function actually did (see func metal_paved).
export METAL_DONE_FILE_PAVED="${METAL_DONE_FILE_PAVED:-/tmp/metalpave.done}"

##############################################################################
# constant: METAL_SUBSYSTEMS
#
# PIPE-DELIMITED-LIST of SUBSYSTEMS to acknowledge from `lsblk` queries; anything listed here is in
# the cross-hairs for wiping and formatting.
# NOTE: To find values for this, run `lsblk -b -l -d -o SIZE,NAME,TYPE,SUBSYSTEMS`
# MAINTAINER NOTE: DO NOT ADD USB or ANY REMOVABLE MEDIA TRANSPORT in order to mitigate accidents.
export METAL_SUBSYSTEMS="${METAL_SUBSYSTEMS:-scsi|nvme}"

##############################################################################
# constant: METAL_SUBSYSTEMS_IGNORE
#
# PIPE-DELIMITED-LIST of Transports to acknowledge from `lsblk` queries; these subsystems are
# excluded from any operations performed by this dracut module.
# NOTE: To find values for this, run `lsblk -b -l -d -o SIZE,NAME,TYPE,SUBSYSTEMS`
export METAL_SUBSYSTEMS_IGNORE="${METAL_SUBSYSTEMS_IGNORE:-usb}"

##############################################################################
# costant: METAL_FSTAB
#
# FSTAB for any partition created from a dracut-metal module.
export METAL_FSTAB="${METAL_FSTAB:-/etc/fstab.metal}"

##############################################################################
# constant: METAL_FSOPTS_XFS
#
# COMMA-DELIMITED-LIST of fsopts for XFS
export METAL_FSOPTS_XFS="${METAL_FSOPTS_XFS:-defaults}"

##############################################################################
# constant: METAL_DISK_SMALL
#
# Define the size that is considered to fit the "small" disk form factor. These
# usually serve critical functions.
export METAL_DISK_SMALL="${METAL_DISK_SMALL:-375809638400}"

##############################################################################
# constant: METAL_DISK_LARGE
#
# Define the size that is considered to fit the "large" disk form factor. These
# are commonly if not always used as ephemeral disks.
export METAL_DISK_LARGE="${METAL_DISK_LARGE:-1048576000000}"

##############################################################################
# constant: METAL_IGNORE_THRESHOLD
#
# Omit any devices smaller than this size.
export METAL_IGNORE_THRESHOLD="${METAL_IGNORE_THRESHOLD:-0}"

##############################################################################
# function: _trip_udev
#
# _trip_udev will call udevadm triggers to settle
# this is useful for populating /dev/disk/by-label/ after FS changes.
_trip_udev() {
  udevadm settle >&2
}

##############################################################################
# function: _overlayFS_path_spec
#
# Return a dracut-dmsquash-live friendly name for an overlayFS to pair with a booting squashFS.
# example:
#
#   overlay-SQFSRAID-cfc752e2-ebb3-4fa3-92e9-929e599d3ad2
#
_overlayFS_path_spec() {
  # if no label is given, grab the default array's UUID and use the default label
  if [ -b "/dev/disk/by-${SQFS_DRIVE_SCHEME,,}/${SQFS_DRIVE_AUTHORITY}" ]; then
    echo "overlay-${SQFS_DRIVE_AUTHORITY:-SQFSRAID}-$(blkid -s UUID -o value "/dev/disk/by-${SQFS_DRIVE_SCHEME,,}/${SQFS_DRIVE_AUTHORITY}")"
  else
    echo "overlay-${SQFS_DRIVE_AUTHORITY:-SQFSRAID}-$(blkid -s UUID -o value /dev/md/SQFS)"
  fi
}

##############################################################################
# function: metal_die
#
# Wait for dracut to settle and die with an error message
#
# Optionally provide -b to reset the system.
metal_die() {
  local _reset=0
  local bootcurrent
  if [ "$1" = "-b" ]; then
    _reset=1
    shift
  fi
  type die
  echo >&2 "metal_die: $*"
  echo >&2 "GitHub/Docs: ${METAL_DOCS_URL}/README.adoc"
  sleep 30 # Leaving time (30seconds) for console/log buffers to catch up.
  if [ "$_reset" = 1 ]; then

    echo >&2 'A reset was requested ... '

    if command -v efibootmgr > /dev/null 2>&1; then
      echo >&2 'Setting bootnext to bootcurrent ...'
      bootcurrent="$(efibootmgr | grep -i bootcurrent | awk '{print $NF}')"
      efibootmgr -n "$bootcurrent" > /dev/null
    fi

    if [ "${METAL_DEBUG:-0}" = 0 ]; then
      echo b > /proc/sysrq-trigger
    else
      echo >&2 'This server is running in debug mode, the reset was ignored.'
    fi
  else
    die
  fi
}

##############################################################################
# function: metal_scand
#
# Returns a sorted, space delimited list of disks. Each element in the list is
# a tuple representing a disk; the size of the disk (in bytes), and
# device-mapper name.
#
# usage:
#
#     metal_scand
#
# output:
#
#     10737418240,sdd 549755813888,sda 549755813888,sdb 1099511627776,sdc
#
metal_scand() {
  echo -n "$(lsblk -b -l -d -o SIZE,NAME,TYPE,SUBSYSTEMS \
    | grep -E '('"$METAL_SUBSYSTEMS"')' \
    | grep -v -E '('"$METAL_SUBSYSTEMS_IGNORE"')' \
    | sort -h \
    | grep -vE 'p[0-9]+$' \
    | awk '{print ($1 > '"$METAL_IGNORE_THRESHOLD"') ? $1 "," $2 : ""}' \
    | tr '\n' ' ' \
    | sed 's/ *$//')"
}

##############################################################################
# function: metal_resolve_disk
#
# Given a disk tuple from metal_scand and a minimum size, print the disk if it's
# larger than or equal to the given size otherwise print nothing.
# Also verified whether the disk has children or not, if it does then it's not
# eligible. Since all disks are wiped to start with, if a disk has children when
# this function would be called then it's already spoken for.
#
# This is useful for iterating through a list of devices and ignoring ones that
# are insufficient.
#
# usage:
#
#   metal_resolve_disk size,name floor/minimum_size
#
metal_resolve_disk() {
  local disk=${1:-}
  local minimum_size=${2:-}
  local disk_dev_name
  local disk_dev_size
  if [ -z "$disk" ] || [ -z "$minimum_size" ]; then
    return
  fi
  disk_dev_name="${disk#*,}"
  disk_dev_size="${disk%,*}"

  # Only consider disks without children.
  if ! lsblk --fs --json "/dev/${disk_dev_name}" | grep -q children; then
    if [ "${disk_dev_size}" -ge "${minimum_size}" ]; then
      echo -n "$disk_dev_name"
    fi
  fi
}

##############################################################################
# function: metal_paved
#
# Returns 0 if the pave has completed, 1 otherwise.
#
# usage:
#
#   To wait on the wipe in an initqueue script:
#
#      metal_paved || exit 1
#
metal_paved() {
  local rc
  if [ -f "$METAL_DONE_FILE_PAVED" ]; then
    rc="$(cat "$METAL_DONE_FILE_PAVED")"
    case "$rc" in
      1)
        # 1 indicates the pave function ran and the disks were wiped.
        return 0
        ;;
      0)
        # 0 indicates the pave function was cleanly bypassed.
        return 0
        ;;
      *)
        echo >&2 "Wipe has emitted an unknown error code: $rc"
        return 2
        ;;
    esac
  else
    # No file indicates the wipe function hasn't been called yet.
    echo >&2 "No sign of wipe function being called (yet). $METAL_DONE_FILE_PAVED was not found"
    return 1
  fi
}

##############################################################################
# function: disks_exist
#
# Returns 0 if disks exist, 1 otherwise.
# Checks for:
#
#   - /dev/sd*
#   - /dev/nvme*
#
# usage:
#
#   To wait on disks to exist:
#
#      disks_exist || exit 1
#
disks_exist() {

  # Wait for devices to exist
  if ls /dev/sd* > /dev/null 2>&1; then

    # SD devices discovered.
    return 0
  elif ls /dev/nvme* > /dev/null 2>&1; then

    # NVME devices discovered.
    return 0
  fi

  # No block devices detected.
  return 1
}
