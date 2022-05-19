#!/bin/bash
# metal-lib.sh for metalmdsquash and other metal dracut modules that
# depend on functions in this library. Such as:
# - https://github.com/Cray-HPE/dracut-metal-dmk8s
# - https://github.com/Cray-HPE/dracut-metal-luksetcd
#
# MAINTAINER NOTE: these functions should not be complicated!
# - constant       : A constant used throughout this module and dependent modules.
# - core function  : A function that must not fail to execute when this library loads.
# - function       : A function that can be used by any dracut module sourcing this library.


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
    type die > /dev/null 2>&1 || . $lib
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
metal_die() {
    type die
    echo >&2 "metal_die: $*"
    echo >&2 "GitHub/Docs: https://github.com/Cray-HPE/dracut-metal-mdsquash"
    sleep 30 # Leave time for console/log buffers to catch up.
    die
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
    set -x
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
