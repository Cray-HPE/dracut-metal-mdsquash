#!/bin/sh
#
# Copyright 2020 Hewlett Packard Enterprise Development LP
#
# metal.server=metal_uri_scheme:metal_authority_path
#
# Together the metal_uri_scheme:metal_authority_path should form a valid URI, like:
#
#	http://api-gateway.nmn/api/path/to/service
#	http://pit
#	file:/var/my_image
#
# If metal_uri_scheme:
#
#  - file: Squashfs packaged with the initrd image.
#	- metal_authority_path: /path to obtain image.
#  - http: Squashfs found at specificed url
#       - metal_authority_path: //authority/path to obtain image.
#
# no-wipe: This is insurance for disks, setting to 1 prevents (re)creation of RAID partitions, devices, and all file-system formatting.
#          Upgrades can and sould set this - if the expected filesystems do not exist then this should be set to 0.
# > metal.no-wipe=1  <- SAFETY: Do not format, invoke mdadm, or partition anything.
# > metal.no-wipe=0  <- DEFAULT: run normally; make filesystems and RAID devices if not found.
#
#### Debug Options:
#
# These should only be used for debugging, either for enabling a
# development environment, or for afixing to a lab system.
#
# Some of these options are third-party, and their documentation can be found here:
#
#   https://manpages.debian.org/testing/dracut-core/dracut.cmdline.7.en.html#Booting_live_images
#
# BEWARE: Do not adjust the following options unless you, the administrator, know what the side-effects will entail.
#         This is a reminder that DATA LOSS can occur if these options are used incorrectly; it is recommended to leave
#         leave these set as-is for metal systems, especially UPGRADES to shasta-1.4.X.
#
# debug: Print everything this module does.
# > metal.debug=1
# > metal.debug=0
#
# disks: Number of disks for the RAIDs, recommended to set `2`. Disks are waited for, sorted, and then
#        this number is taken from the top (lowest first).
# > metal.disks=2
#
# md-level: Type of RAID.
# > metal.md-level=mirror
#
# live.overlay.reset: Set to yes to erase and reset the overlayFS
# live.overlay.reset: Set to yes to erase and reset the overlayFS
# > rd.live.overlay.reset=1
#
# live.overlay.readonly: Set to mark the entire overlayFS as read-only.
# > rd.live.overlay.readonly=1
#
# live.dir: This can change where the squashFS is stored within its storage.
# > rd.live.dir=LiveOS
#
# live.overlay: This determines where our block-device is for the persistent overlay.
# > rd.live.overlay=label=ROOTRAID
#
# live.squashimg: This specifies the name of the squashFS file to look for.
# > rd.live.squashimg=filesystem.squashfs
#
# sqfs-md-size: Size of the SquashFS storage. Shasta-1.3 and earlier installs with
#               the SQFSRAID partition are 100GB. Customizing this would be useful for
#               virtual environments or ad-hoc labs. Recommended to leave untouched.
#               This value is read as Gigabytes.
# > metal.sqfs-md-size=100
#
type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
getargbool 0 metal.debug -d -y metal_debug && metal_debug=1

metal_disks=$(getargnum 2 1 10 metal.disks)
getargbool 0 metal.no-wipe -d -y metal_nowipe && metal_nowipe=1 || metal_nowipe=0
metal_overlay=$(getarg rd.live.overlay)
[ -z "${metal_overlay}" ] && metal_overlay=LABEL=ROOTRAID
metal_server=$(getarg metal.server=)

export metal_debug
export metal_disks
export metal_nowipe
export metal_overlay
export metal_server
