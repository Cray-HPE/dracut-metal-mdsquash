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
# metal-kdump.sh
# do not use set -u or -e because it breaks usage of /lib/dracut-lib.sh
set -o pipefail

[ "${METAL_DEBUG:-0}" = 0 ] || set -x

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
command -v _overlayFS_path_spec > /dev/null 2>&1 || . /lib/metal-lib.sh

root=$(getarg root)
case "$root" in
  kdump)

    # Ensure nothing else in this script is invoked in this case.
    exit 0
    ;;
esac

oval_drive_scheme=${METAL_OVERLAY%%=*}
oval_drive_authority=${METAL_OVERLAY#*=}
overlayfs_mountpoint="$(lsblk -o MOUNTPOINT -nr "/dev/disk/by-${oval_drive_scheme,,}/${oval_drive_authority}")"

overlayfs_path=$(_overlayFS_path_spec)
[ -z "${overlayfs_path}" ] && warn 'Failed to resolve overlayFS directory. kdump will not generate a system.map in the event of a crash.'
live_dir=$(getarg rd.live.dir -d live_dir)
[ -z "${live_dir}" ] && live_dir="LiveOS"

##############################################################################
# function: overlayfs_dump_dir
#
# - Creates the KDUMP_SAVEDIR for kdump to save crashes into.
# - Creates a README.txt file that describes the created directories on the overlayFS base partition.
function overlayfs_dump_dir {

  local kdump_savedir
  local kdump_savedir_parentdir
  local link_target

  if [ -z "${overlayfs_mountpoint}" ]; then
    die "overlayfs_mountpoint was not set!"
  fi

  kdump_savedir="$(grep -oP 'KDUMP_SAVEDIR="file://\K\S+[^"]' /run/rootfsbase/etc/sysconfig/kdump)"
  kdump_savedir="${kdump_savedir/"${overlayfs_mountpoint}"/}"
  kdump_savedir="${kdump_savedir#/}" # Trim leading slash for easier path joining.

  if [ ! -d "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/${kdump_savedir}" ]; then
    mkdir -pv "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/${kdump_savedir}"
  fi

  # Create only the leading directories, removing the final one. The final directory will become a symlink.
  mkdir -pv "${overlayfs_mountpoint}/${kdump_savedir}" && rm -rf "${overlayfs_mountpoint:?}/${kdump_savedir}"
  kdump_savedir_parentdir="$(dirname "$kdump_savedir")"
  if [ "$kdump_savedir_parentdir" = '.' ]; then
    kdump_savedir_parentdir=""
  fi
  link_target="$(realpath -s --relative-to="${overlayfs_mountpoint}/${kdump_savedir_parentdir}" "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/${kdump_savedir}")"
  ln -snf "$link_target" "${overlayfs_mountpoint}/${kdump_savedir}"

  cat << EOF > "${overlayfs_mountpoint}/README.txt"
This directory contains two supporting directories for KDUMP
- boot/ is a symbolic link that enables KDUMP to resolve the kernel and system symbol maps (for legacy kdump<1.9)
- $kdump_savedir/ is a directory that KDUMP will dump into, this directory is bind mounted to /var/crash on the booted system.
EOF
}

##############################################################################
# function: load_boot_images (LEGACY: kdump<1.9)
#
# Populates the overlayFS boot directory with a kernel and System.map that kdump will use for dumps.
# This copies the currently selected kernel, keying off of the symbolic link at /sysroot/boot/vmlinuz.
# That symbolic link will point to the currently loaded kernel on boot.
# NOTE: When running kexec, the new kernel will be copied into the target boot directory by the overlayFS itself.
function load_boot_images {

  local kernel_image
  local kernel_ver
  local system_map

  if [ -z "${overlayfs_mountpoint}" ]; then
    die "overlayfs_mountpoint was not set!"
  fi

  # LEGACY (kdump<1.9)
  if [ ! -d "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot" ]; then
    mkdir -pv "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot"
  fi
  ln -snf "./${live_dir}/${overlayfs_path}/boot" "${overlayfs_mountpoint}/boot"

  # Check the overlayFS first for the kernel version, incase a new kernel was installed on a prior boot.
  # Otherwise get the kernel version from the squashFS image.
  if [ -f "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot/vmlinuz" ]; then
    kernel_ver=$(readlink "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot/vmlinuz" | grep -oP 'vmlinuz-\K\S+')
  elif [ -f /run/rootfsbase/boot/vmlinuz ]; then
    kernel_ver=$(readlink /run/rootfsbase/boot/vmlinuz | grep -oP 'vmlinuz-\K\S+')
  else
    warn 'Failed to resolve the kernel file in /boot, kdump will not generate a system.map in the event of a crash.'
  fi

  # If the kernel was upgraded, then the image ill already exist in the OverlayFS.
  if [ ! -f "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot/vmlinux-${kernel_ver}.gz" ]; then

    # If the kernel image does not exist, then this is a deployment (first-boot) and the kernel needs to be copied.
    if [ -f "/run/rootfsbase/boot/vmlinux-${kernel_ver}.gz" ]; then
      kernel_image=/run/rootfsbase/boot/vmlinux-${kernel_ver}.gz
      cp -pv "$kernel_image" "${overlayfs_mountpoint}/boot/"
    else
      warn "Failed to resolve vmlinux-${kernel_ver}.gz; kdump will produce incomplete dumps."
    fi
  else
    info "vmlinux-${kernel_ver}.gz is already present in the boot directory for kdump"
  fi

  # If the kernel was upgraded, then the System.map ill already exist in the OverlayFS.
  if [ ! -f "${overlayfs_mountpoint}/${live_dir}/${overlayfs_path}/boot/System.map-${kernel_ver}" ]; then

    # If the System.map does not exist, then this is a deployment (first-boot) and the System.map needs to be copied.
    if [ -f "/run/rootfsbase/boot/System.map-${kernel_ver}" ]; then
      system_map=/run/rootfsbase/boot/System.map-${kernel_ver}
      cp -pv "${system_map}" "${overlayfs_mountpoint}/boot/"
    else
      warn "Failed to resolve System.map-${kernel_ver}; kdump will produce incomplete dumps."
    fi
  else
    info "System.map-${kernel_ver} is already present in the boot directory for kdump"
  fi

}

OVERLAYFS=0
getargbool 0 rd.live.overlay.overlayfs && OVERLAYFS=1
if [ "$OVERLAYFS" -eq 1 ]; then
  info "OverlayFS detected. Configuring kdump to redirect to the persistent overlayFS."
  overlayfs_dump_dir
  load_boot_images
else
  case "$root" in
    live:*)
      warn "System is running in RAM without an overlayFS or persistent disk. kdump may fail unless it is configured by other means."
      ;;
  esac
fi
