#!/bin/bash
# metal-lib.sh for metalmdsquash and other metal dracut modules
# this script provides the base library for metal, common functions
# MAINTAINER NOTE: these functions should not be complicated
type die > /dev/null 2>&1 || . /lib/dracut-lib.sh

# PIPE-DELIMITED-LIST of Transports to acknowledge from `lsblk` queries; these transports are 
# exclusively cleaned and partitioned, all others on the node are left alone.
# MAINTAINER NOTE: DO NOT ADD USB or ANY REMOVABLE MEDIA TRANSPORT in order to mitigate accidents.
export metal_transports="sata|nvme|sas"

# _trip_udev will call udevadm triggers to settle
# this is useful for populating /dev/disk/by-label/ after FS changes.
_trip_udev() {
    udevadm settle >&2
}

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
## Wait for dracut to settle and die with an error message
metal_die() {
    type die
    echo >&2 "metal_die: $*"
    echo >&2 "GitHub/Docs: https://github.com/Cray-HPE/dracut-metal-mdsquash"
    sleep 30 # Leave time for console/log buffers to catch up.
    die
}

##############################################################################
## Sorts a list of disks, returning the first disk that's larger than the 
## given constraint.
##
## The output of this lsblk command is ideal for this function:
##
##   lsblk -b -l -o SIZE,NAME,TYPE,TRAN | grep -E '(sata|nvme|sas)' | sort -h | awk '{print $1 "," $2}' 
##
## usage:
##
##   metal_resolve_disk "size,name [size,name]" floor/minimum_size
## 
## example(s):
##
##   metal_resolve_disk "480103981056,sdc 1920383410176,sdb" 1048576000000
metal_resolve_disk() {
    local disks=$1
    local minimum_size=$2
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
