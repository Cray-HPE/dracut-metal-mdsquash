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
# module-setup.sh

# called by dracut cmd
check() {
    require_binaries mdadm xfs_admin || return 1
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
    inst_multiple cut curl diff efibootmgr head lsblk mkfs.ext4 mkfs.vfat mkfs.xfs parted seq sort tail wc vgscan xfs_admin
    # install our callables
    inst_simple "$moddir/mdadm.conf" "/etc/mdadm.conf"
    inst_simple "$moddir/metal-md-lib.sh" "/lib/metal-md-lib.sh"
    inst_simple "$moddir/metal-lib.sh" "/lib/metal-lib.sh"
    inst_script "$moddir/metal-md-disks.sh" /sbin/metal-md-disks
    inst_script "$moddir/metal-md-scan.sh" /sbin/metal-md-scan
    # install our hooks
    inst_hook cmdline 10 "$moddir/parse-metal.sh"
    inst_hook pre-udev 10 "$moddir/metal-genrules.sh"

    # before loading the copy any new fstab.metal into place
    # copy udev rules into the sysroot available during pre-pivot
    inst_hook pre-mount 10 "$moddir/metal-kdump.sh"
    inst_hook pre-pivot 10 "$moddir/metal-update-fstab.sh"
    inst_hook pre-pivot 11 "$moddir/metal-udev.sh"

    # dracut needs to know we must have the initqueue, we have no initqueue hooks to inherit the call.
    dracut_need_initqueue
}
