#!/bin/sh
# metal-lib.sh for metalmdsquash and other metal dracut modules
# this script provides the base library for metal, common functions
# MAINTAINER NOTE: these functions should not be complicated
type die > /dev/null 2>&1 || . /lib/dracut-lib.sh

# _trip_udev will call udevadm triggers to settle
# this is useful for populating /dev/disk/by-label/ after FS changes.
_trip_udev() {
    udevadm settle >&2
}

_overlayFS_path_spec() {
    [ -z $sqfs_drive_scheme ] || [ -z "$sqfs_drive_authority" ] && echo ''
    echo "overlay-${sqfs_drive_authority}-$(blkid -s UUID -o value /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority})"
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