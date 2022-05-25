#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
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
[ "${metal_debug:-0}" = 0 ] || set -x

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
    >&2 cat << EOF
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
# constant: metal_transports
#
# PIPE-DELIMITED-LIST of Transports to acknowledge from `lsblk` queries; these transports are 
# exclusively cleaned and partitioned, all others on the node are left alone.
# MAINTAINER NOTE: DO NOT ADD USB or ANY REMOVABLE MEDIA TRANSPORT in order to mitigate accidents.
export metal_transports="sata|nvme|sas"

##############################################################################
# costant: metal_fstab
#
# FSTAB for any partition created from a dracut-metal module.
export metal_fstab=/etc/fstab.metal

##############################################################################
# constant: metal_fsopts_xfs
#
# COMMA-DELIMITED-LIST of fsopts for XFS
export metal_fsopts_xfs=noatime,largeio,inode64,swalloc,allocsize=13107

##############################################################################
# constant: metal_disk_small
#
# Define the size that is considered to fit the "small" disk form factor. These
# usually serve critical functions.
export metal_disk_small=524288000000

##############################################################################
# constant: metal_disk_large
#
# Define the size that is considered to fit the "large" disk form factor. These 
# are commonly if not always used as ephemeral disks.
export metal_disk_large=1048576000000

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
    if [ -b /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority} ]; then
        echo "overlay-${sqfs_drive_authority:-SQFSRAID}-$(blkid -s UUID -o value /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority})"
    else
        echo "overlay-${sqfs_drive_authority:-SQFSRAID}-$(blkid -s UUID -o value /dev/md/SQFS)"
    fi
}

##############################################################################
# function: metal_die
#
# Wait for dracut to settle and die with an error message
#
# Optionally provide -b to reset the system.
metal_die() {
    local reset=0
    local bootcurrent
    if [ "$1" = "-b" ]; then
        _reset=1
        shift
    fi
    type die
    echo >&2 "metal_die: $*"
    echo >&2 "GitHub/Docs: https://github.com/Cray-HPE/dracut-metal-mdsquash"
    sleep 30 # Leaving time (30seconds) for console/log buffers to catch up.
    if [ "$_reset" = 1 ]; then
        
        echo >&2 'A reset was requested ... '
        
        if command -v efibootmgr >/dev/null 2>&1; then
            echo >&2 'Setting bootnext to bootcurrent ...'
            bootcurrent="$(efibootmgr | grep -i bootcurrent | awk '{print $NF}')"
            efibootmgr -n $bootcurrent >/dev/null
        fi
        
        if [ "${metal_debug:-0}" = 0 ]; then
            echo b >/proc/sysrq-trigger
        else
            echo >&2 'This server is running in debug mode, the reset was ignored.'
        fi
    else
        die
    fi
}


##############################################################################
# function: metal_resolve_disk
#
# Function returns a space delemited list of tuples, each tuple contains the
# size (in bytes) of a disk, and the disk handle itself. This output is
# compatible with metal_resolve_disk.
#
# usage:
#
#   Return disks except, ignoring the first two used by the OS:
# 
#       metal_scand $((metal_disks + 1))
# 
#   Return the OS disks:
#
#      md_disks=();for disk in seq 1 $metal_disks; do md_disk=$(metal_scand $disk | cut -d ' ' -f1) ; echo $md_disk; md_disks+=( $md_disk ); done; echo ${md_disks[@]}
#
metal_scand() {
    local disk_offset=${1:-$metal_disks}
    local disks
    disks="$(lsblk -b -l -d -o SIZE,NAME,TYPE,TRAN |\
        grep -E '('"$metal_transports"')' |\
        sort -h |\
        grep -vE 'p[0-9]+$' |\
        awk '{print $1 "," $2}' |\
        tail -n +${disk_offset} |\
        tr '\n' ' ' |\
        sed 's/ *$//')"
    echo $disks
}

##############################################################################
# function: metal_resolve_disk
#
# Sorts a list of disks, returning the first disk that's larger than the 
# given constraint.
#
# The output of this lsblk command is ideal for this function:
#
#   lsblk -b -l -o SIZE,NAME,TYPE,TRAN | grep -E '(sata|nvme|sas)' | sort -h | awk '{print $1 "," $2}' 
#
# usage:
#
#   metal_resolve_disk "size,name [size,name]" floor/minimum_size
#
# example(s):
#
#   metal_resolve_disk "480103981056,sdc 1920383410176,sdb" 1048576000000
metal_resolve_disk() {
    local disks=$1
    local minimum_size=$(echo $2 | sed 's/,.*//')
    local found=0
    for disk in $disks; do
        name="$(echo $disk | sed 's/,/ /g' | awk '{print $2}')"
        size="$(echo $disk | sed 's/,/ /g' | awk '{print $1}')"
        if [ "${size}" -gt $minimum_size ]; then
            found=1
        fi 
    done
    printf $name
    [ $found = 1 ] && return 0 || return 1
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
    if [ -f /tmp/metalpave.done ]; then
        rc="$(cat /tmp/metalpave.done)"
        case "$rc" in
            1)
                # 1 indicates the pave function ran and the disks were wiped.
                echo >&2 'Disks have been wiped.'
                return 0
                ;;
            0)
                # 0 indicates the pave function was cleanly bypassed.
                echo >&2 'Wipe was skipped.'
                return 0
                ;;
            *)
                echo >&2 "Wipe has emitted an unknown error code: $rc"
                return 1
                ;;
        esac
    else
        # No file indicates the wipe function hasn't been called.
        echo >&2 'Wipe pending or cancelled.'
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
