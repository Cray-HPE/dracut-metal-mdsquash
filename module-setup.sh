#!/bin/bash
# module-setup.sh for metalmdsquash

# called by dracut
check() {
    require_binaries mdadm || return 1
    return 0
}

# called by dracut
depends() {
    # mdraid is needed for using RAIDs
    # network is needed for fetching squashfs.
    echo network mdraid
    return 0
}

installkernel() {
    instmods hostonly='' loop raid1
}

# called by dracut
install() {
    inst_multiple curl parted mkfs.ext4 mkfs.xfs lsblk sort head mkfs.vfat

    inst_simple "$moddir/metal-md-lib.sh" "/lib/metal-md-lib.sh"
    inst_script "$moddir/metal-md-disks.sh" /sbin/metal-md-disks
    inst_script "$moddir/metal-md-scan.sh" /sbin/metal-mdscan

    inst_hook cmdline 10 "$moddir/parse-metal.sh"
    inst_hook pre-udev 10 "$moddir/metal-genrules.sh"

    dracut_need_initqueue
}
