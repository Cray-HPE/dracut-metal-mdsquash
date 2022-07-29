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
# metal-kdump.sh
# do not use set -u or -e because it breaks usage of /lib/dracut-lib.sh
set -o pipefail

[ "${metal_debug:-0}" = 0 ] || set -x

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
command -v _overlayFS_path_spec > /dev/null 2>&1 || . /lib/metal-lib.sh

case "$(getarg root)" in 
    kdump)
        /sbin/initqueue --settled /sbin/metal-md-scan
        
        # Ensure nothing else in this script is invoked in this case.
        exit 0
        ;;
esac

OVERLAYFS_PATH=$(_overlayFS_path_spec)
[ -z ${OVERLAYFS_PATH} ] && warn 'Failed to resolve overlayFS directory. kdump will not generate a system.map in the event of a crash.'
LIVE_DIR=$(getarg rd.live.dir -d live_dir)
[ -z "${LIVE_DIR}" ] && LIVE_DIR="LiveOS"
    

##############################################################################
# function: prepare
#
# - Creates the KDUMP_SAVEDIR for kdump to save crashes into.
# - Creates a symbolic link that /kdump/boot will resolve for finding the kernel and System.map
# - Updates the metal fstab to bind mount the KDUMP_SAVEDIR to /var/crash on a running system through metalfs.service
# - Creates a README.txt file that describes the created directories on the overlayFS base partition. 
function prepare {

    local kernel_savedir

    kernel_savedir="$(grep -oP 'KDUMP_SAVEDIR="file:///\K\S+[^"]' /run/rootfsbase/etc/sysconfig/kdump)"

    if [ ! -d "/run/initramfs/overlayfs/${kernel_savedir}" ]; then
        mkdir -pv "/run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/var/crash"
    fi
    ln -snf "./${LIVE_DIR}/${OVERLAYFS_PATH}/var/crash" "/run/initramfs/overlayfs/${kernel_savedir}"

    if [ ! -d "/run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot" ]; then
        mkdir -pv "/run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot"
    fi
    ln -snf "./${LIVE_DIR}/${OVERLAYFS_PATH}/boot" /run/initramfs/overlayfs/boot
    
    cat << EOF > /run/initramfs/overlayfs/README.txt
This directory contains two supporting directories for KDUMP
- boot/ is a symbolic link that enables KDUMP to resolve the kernel and system symbol maps.
- $crash_dir/ is a directory that KDUMP will dump into, this directory is bind mounted to /var/crash on the booted system.
EOF
}

##############################################################################
# function: load_boot_images
#
# Populates the overlayFS boot directoy with a kernel and System.map that kdump will use for dumps.
# This copies the currently selected kernel, keying off of the symbolic link at /sysroot/boot/vmlinuz.
# That symbolic link will point to the currently loaded kernel on boot.
# NOTE: When running kexec, the new kernel will be copied into the target boot directory by the overlayFS itself.
function load_boot_images {

    local kernel_image
    local kernel_ver
    local system_map
    
    # Check the overlayFS first for the kernel version, incase a new kernel was installed on a prior boot.
    # Otherwise get the kernel version from the squashFS image.
    if [ -f /run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot/vmlinuz ]; then
        kernel_ver=$(readlink /run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot/vmlinuz | grep -oP 'vmlinuz-\K\S+')
    elif [ -f /run/rootfsbase/boot/vmlinuz ]; then
        kernel_ver=$(readlink /run/rootfsbase/boot/vmlinuz | grep -oP 'vmlinuz-\K\S+')
    else
        warn 'Failed to resolve the kernel file in /boot, kdump will not generate a system.map in the event of a crash.'
    fi

    # If the kernel was upgraded, then the image ill already exist in the OverlayFS.
    if [ ! -f /run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot/vmlinux-${kernel_ver}.gz ]; then

        # If the kernel image does not exist, then this is a deployment (first-boot) and the kernel needs to be copied.
        if [ -f /run/rootfsbase/boot/vmlinux-${kernel_ver}.gz ]; then
            kernel_image=/run/rootfsbase/boot/vmlinux-${kernel_ver}.gz
            cp -pv "$kernel_image" /run/initramfs/overlayfs/boot/
        else
            warn "Failed to resolve vmlinux-${kernel_ver}.gz; kdump will produce incomplete dumps."
        fi
    else
        info "vmlinux-${kernel_ver}.gz is already present in the boot directory for kdump"
    fi
    
    # If the kernel was upgraded, then the System.map ill already exist in the OverlayFS.
    if [ ! -f /run/initramfs/overlayfs/${LIVE_DIR}/${OVERLAYFS_PATH}/boot/System.map-${kernel_ver} ]; then

        # If the System.map does not exist, then this is a deployment (first-boot) and the System.map needs to be copied.
        if [ -f /run/rootfsbase/boot/System.map-${kernel_ver} ]; then
            system_map=/run/rootfsbase/boot/System.map-${kernel_ver}
            cp -pv ${system_map} /run/initramfs/overlayfs/boot/
        else
            warn "Failed to resolve System.map-${kernel_ver}; kdump will produce incomplete dumps."
        fi
    else
        info "System.map-${kernel_ver} is already present in the boot directory for kdump"
    fi

}

prepare
load_boot_images
