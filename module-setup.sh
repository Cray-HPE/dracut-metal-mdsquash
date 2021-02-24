#!/bin/bash
# Copyright 2021 Hewlett Packard Enterprise Development LP
# module-setup.sh for metalmdsquash

# called by dracut cmd
check() {
    require_binaries mdadm || return 1
    return 0
}

# called by dracut cmd
depends() {
    # mdraid is needed for using RAIDs
    # network is needed for fetching squashfs.
    echo network mdraid
    return 0
}

# called by dracut cmd
installkernel() {
    instmods hostonly='' loop raid1
}

# called by dracut
install() {
    inst_multiple curl head lsblk mkfs.ext4 mkfs.vfat mkfs.xfs parted sort
    # install our callables
    inst_simple "$moddir/metal-md-lib.sh" "/lib/metal-md-lib.sh"
    inst_script "$moddir/metal-md-disks.sh" /sbin/metal-md-disks
    inst_script "$moddir/metal-md-scan.sh" /sbin/metal-md-scan
    # install our hooks
    inst_hook cmdline 10 "$moddir/parse-metal.sh"
    inst_hook pre-udev 10 "$moddir/metal-genrules.sh"
    # before loading the copy any new fstab.metal into place
    inst_hook pre-pivot 10 "$moddir/metal-update-fstab.sh"
    # FIXME: Causes cloud-init to fail setting up.
    inst_hook pre-pivot 20 "$moddir/metal-udev.sh"
    # dracut needs to know we must have the initqueue, we have no initqueue hooks to inherit the call.
    dracut_need_initqueue
}
