#!/bin/bash

PATH=/usr/sbin:/usr/bin:/sbin:/bin

[ "${metal_debug:-0}" = 1 ] && echo "$@" && set -x

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
type metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

# Honor and obey dmsquash parameters, if a user sets a different rd.live.dir on the cmdline then it
# should be reflected here as well.

# allow the initrd to change names
initrd=$(getarg initrd=)
[ -z "${initrd}" ] && initrd="initrd.img.xz"

# these use getargnum from /lib/dracut-lib.sh; <default> <min> <max>
metal_sqfs_size_end=$(getargnum 25 25 100 metal.sqfs-md-size)
overlay_size_end=$(getargnum 150 25 200 metal.oval-md-size)
auxillary_size_end=$(getargnum 150 0 200 metal.aux-md-size)

# this is passed to mdadm during creation; default is redundant mirrors
metal_mdlevel=$(getarg metal.md-level=)
[ -z "${metal_mdlevel}" ] && metal_mdlevel=mirror

# Handle single-disk situations.
mdadm_raid_devices="--raid-devices=$metal_disks"
[ $metal_disks = 1 ] && mdadm_raid_devices="$mdadm_raid_devices --force"

# directory to download new artifacts to, and look for old artifacts in.
live_dir=$(getarg rd.live.dir -d live_dir)
[ -z "${live_dir}" ] && live_dir="LiveOS"

# name of the squashFS file to download from metal.server, or to look for inside of rd.live.dir
squashfs_file=$(getarg rd.live.squashimg=)
[ -z "${squashfs_file}" ] && squashfs_file=filesystem.squashfs

# Safeguard, if the hostname is missing - try searching for a vanilla filesystem.squashfs file.
[ "${squashfs_file}" = '.squashfs' ] && squashfs_file=filesystem.squashfs

if [[ -n "$metal_server" ]]; then
    # this works for breaking the protocol off and finding the base path.
    IFS=':' read -ra ADDR <<< "$metal_server"
    metal_uri_scheme=${metal_server%%:*}
    metal_uri_authority=${metal_server#*:}
    if [ -z "${metal_uri_scheme}" ] || [ -z "${metal_uri_authority}" ]; then
        metal_die "Failed to parse the scheme, authority, and path for URI ${metal_server}"
    fi

    # these local vars are only used for file copies, in http|https they're not used at all.
    metal_local_dir=${metal_uri_authority%%\?*}
    metal_local_url=${metal_server#*\?}
    metal_local_url_authority=${metal_local_url#*=}
fi

# rootfallback may be empty, if it is then this block will ignore.
boot_fallback=$(getarg rootfallback=)
boot_drive_scheme=${boot_fallback%%=*}
[ -z "$boot_drive_scheme" ] && boot_drive_scheme=LABEL
boot_drive_authority=${boot_fallback#*=}
[ -z "$boot_drive_authority" ] && boot_drive_authority=BOOTRAID
case $boot_drive_scheme in
    PATH | path | UUID | uuid | LABEL | label)
        info "bootloader will be located on  ${boot_drive_scheme}=${boot_drive_authority}"
        ;;
    '')
        # no-op; drive disabled
        :
        ;;
    *)
        metal_die "Unsupported boot-drive-scheme ${boot_drive_scheme} Supported schemes: PATH, UUID, and LABEL (upper and lower cases)"
        ;;
esac

# root must never be empty; if it is then nothing will boot - dracut will never find anything todo.
root=$(getarg root)
case "$root" in
    live:/dev/*)
        sqfs_drive_url=${root///dev\/disk\/by-}
        sqfs_drive_spec=${sqfs_drive_url#*:}
        sqfs_drive_scheme=${sqfs_drive_spec%%/*}
        sqfs_drive_authority=${sqfs_drive_spec#*/}
        ;;
    live:*)
        sqfs_drive_url=${root#live:}
        sqfs_drive_spec=${sqfs_drive_url#*:}
        sqfs_drive_scheme=${sqfs_drive_spec%%=*}
        sqfs_drive_authority=${sqfs_drive_spec#*=}
        ;;
    kdump)
        info "kdump detected. continuing..."
        ;;
    '')
        warn "No root; root needed - the system will likely fail to boot."
        # do not fail, allow dracut to handle everything in case an operator/admin is doing something.
        ;;
    *)
        warn "alien root! unrecognized root= parameter: root=${root}"
        ;;
esac
# support CDLABEL by overriding it to LABEL, CDLABEL only means anything in other dracut modules
# and those modules will parse it out of root= (not our variable) - normalize it in our context.
[ "${sqfs_drive_scheme}" = 'CDLABEL' ] || sqfs_drive_scheme=LABEL
[ -z "${sqfs_drive_authority}" ] && sqfs_drive_scheme=SQFSRAID
case $sqfs_drive_scheme in
    PATH | path | UUID | uuid | LABEL | label)
        info "SquashFS file is on ${sqfs_drive_scheme}=${sqfs_drive_authority}"
        ;;
    *)
        metal_die "Unsupported sqfs-drive-scheme ${sqfs_drive_scheme}\nSupported schemes: PATH, UUID, and LABEL"
        ;;
esac

IFS='=' read -ra ADDR <<< "${metal_overlay:-LABEL=ROOTRAID}"
oval_drive_scheme=${metal_overlay%%=*}
oval_drive_authority=${metal_overlay#*=}
case "$oval_drive_scheme" in
    PATH | path | UUID | uuid | LABEL | label)
        info "Overlay is on ${oval_drive_scheme}=${oval_drive_authority}"
        ;;
    '')
        # no-op; disabled
        :
        ;;
    *)
        warn "Unsupported oval-drive-scheme ${oval_drive_scheme}"
        info "Supported schemes: PATH, UUID, and LABEL (upper and lower cases)"
        exit 1
        ;;
esac

##############################################################################
## SquashFS Storage
# This area provides a simple partition for fallback boots, and a partition for storing squashFS
# images.
# Pave down a new GPT partition table.
# Partition FAT for EFI files.
# Partition XFS 64bit for handling large files, like squashFS images.
make_raid_store() {

    _trip_udev
    if blkid -s UUID -o value "/dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority^^}"; then
        echo 0 > /tmp/metalsqfsdisk.done && return
    fi

    # Loop through our disks and make our partitions needed for a squashFS storage:
    # - BOOTRAID : For fallback booting.
    # - SQFSRAID : For stowing squashFS images.
    local boot_raid_parts=''
    local sqfs_raid_parts=''
    for disk in $md_disks; do
        parted --wipesignatures -m --align=opt --ignore-busy -s "/dev/$disk" -- mklabel gpt \
            mkpart esp fat32 2048s 500MB set 1 esp on \
            mkpart primary xfs 500MB "${metal_sqfs_size_end}GB"
        _trip_udev
        boot_raid_parts="$(trim $boot_raid_parts) /dev/${disk}1"
        sqfs_raid_parts="$(trim $sqfs_raid_parts) /dev/${disk}2"
    done
    # metadata=0.9 for boot files.
    mdadm --create /dev/md/BOOT --run --verbose --assume-clean --metadata=0.9 --level="$metal_mdlevel" $mdadm_raid_devices ${boot_raid_parts} || metal_die "Failed to make filesystem on /dev/md/BOOT"
    mdadm --create /dev/md/SQFS --run --verbose --assume-clean --metadata=1.2 --level="$metal_mdlevel" $mdadm_raid_devices ${sqfs_raid_parts} || metal_die "Failed to make filesystem on /dev/md/SQFS"

    _trip_udev
    mkfs.vfat -F32 -n "${boot_drive_authority}" /dev/md/BOOT || metal_die 'Failed to format bootraid.'
    mkfs.xfs -f -L "${sqfs_drive_authority}" /dev/md/SQFS || metal_die 'Failed to format squashFS storage.'
    echo 1 > /tmp/metalsqfsdisk.done && info 'SquashFS storage is ready...'
}

##############################################################################
## Persistent OverlayFS
# Create the SquashFS Storage.
# Partition XFS 64bit.
make_raid_overlay() {

    _trip_udev
    if blkid -s UUID -o value "/dev/disk/by-${oval_drive_scheme,,}/${oval_drive_authority^^}"; then
        echo 0 > /tmp/metalovaldisk.done && return
    fi

    local oval_raid_parts=''
    local aux_raid_parts=''
    local oval_end="$((overlay_size_end + metal_sqfs_size_end))"
    local aux_end="$((auxillary_size_end + oval_end))"
    for disk in $md_disks; do
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary xfs "${metal_sqfs_size_end}GB" "${oval_end}GB"
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary "${oval_end}GB" "${aux_end}GB"
        oval_raid_parts="$(trim $oval_raid_parts) /dev/${disk}3" # FIXME: Find partition number vs hard code.
        aux_raid_parts="$(trim $aux_raid_parts) /dev/${disk}4"
    done
    mdadm --create /dev/md/ROOT --assume-clean --run --verbose --metadata=1.2 --level="$metal_mdlevel" $mdadm_raid_devices ${oval_raid_parts} || metal_die "Failed to make filesystem on /dev/md/ROOT"
    mdadm --create /dev/md/AUX --assume-clean --run --verbose --metadata=1.2 --level="$metal_mdlevel" $mdadm_raid_devices ${aux_raid_parts} || metal_die "Failed to make filesystem on /dev/md/AUX"

    _trip_udev
    mkfs.xfs -f -L "${oval_drive_authority}" /dev/md/ROOT || metal_die 'Failed to format overlayFS storage.'
    echo 1 > /tmp/metalovaldisk.done && info 'Overlay storage is ready ...'
}

##############################################################################
## Persistent OverlayFS
# Make our dmsquash-live-root overlayFS.
add_overlayfs() {
    [ -f /tmp/metalovalimg.done ] && return
    [ -f /tmp/metalovaldisk.done ] || make_raid_overlay
    local mpoint=/metal/ovaldisk
    mkdir -p ${mpoint}
    if ! mount -n -t xfs "/dev/disk/by-${oval_drive_scheme,,}/${oval_drive_authority}" "$mpoint"; then

        # try shasta-1.3 formatting or die.
        mount -n -t ext4 "/dev/disk/by-${oval_drive_scheme,,}/${oval_drive_authority}" "$mpoint" \
            || metal_die "Failed to mount ${oval_drive_authority} as xfs or ext4"
    fi

    [ -z "${metal_overlayfs_id}" ] && metal_overlayfs_id="$(_overlayFS_path_spec)"
    mkdir -m 0755 -p \
        "${mpoint}/${live_dir}/${metal_overlayfs_id}" \
        "${mpoint}/${live_dir}/${metal_overlayfs_id}/../ovlwork"
    echo 1 > /tmp/metalovalimg.done && info 'OverlayFS is ready ...'
    umount ${mpoint}
}

##############################################################################
## SquashFS
# Gets the squashFS file from a URL endpoint or a local endpoint.
fetch_sqfs() {
    # TODO: Add md5 check - this may vary between Artifactory/bootstrap and s3/production artifacts at the present time.
    [ -f "$1/${squashfs_file}" ] && echo 0 > /tmp/metalsqfsimg.done && return
    [ -z "$metal_server" ] && warn 'No metal.server=, nothing to download or copy' && echo 0 > /tmp/metalsqfsimg.done && return
    if [ "${metal_uri_scheme}" != "file" ]; then
        (
            set -e
            cd "$1"
            curl -O "${metal_server}/${squashfs_file}" > /dev/null 2>&1 && echo >2 "${squashfs_file} downloaded  ... "
            curl -O "${metal_server}/kernel" > /dev/null 2>&1 && echo >2 'grabbed the kernel it rode in on ... '
            curl -O "${metal_server}/${initrd}" > /dev/null 2>&1 && echo >2 'and its initrd ... '
        ) || warn 'Failed to download ; may retry'
    else
        # File support; copy the authority to tmp; tmp auto-clears on root-pivot.
        [ -z "$metal_local_url_authority" ] && metal_die "Missing LABEL=<FSLABEL> on $metal_server"

        # Mount read-only to prevent harm to the device; we literally just need to pull the files off it.
        mkdir -vp /tmp/source
        mount -n -o ro -L "$metal_local_url_authority" /tmp/source || metal_die "Failed to mount $metal_local_url_authority from $metal_server"
        (
            set -e
            cd "$1"
            cp -pv "/tmp/source/${metal_local_dir#//}/${squashfs_file}" . && echo >2 "copied ${squashfs_file} ... "
            cp -pv "/tmp/source/${metal_local_dir#//}/kernel" . && echo >2 'grabbed the kernel we rode in on ... '
            cp -pv "/tmp/source/${metal_local_dir#//}${initrd}" . && echo >2 'and its initrd ... '
        ) || warn 'Failed to copy ; may retry'
        umount /tmp/source
    fi
    if [ -f "$1/${squashfs_file}" ]; then
        echo 1 > /tmp/metalsqfsimg.done
        info 'Successfully downloaded boot artifacts ...'
        return
    fi
}

##############################################################################
## SquashFS
# Add a local file to squashFS storage.
add_sqfs() {
    # todo: this could maybe move into metal-genrules.sh, preventing any call under kdump.
    if [ $root = "kdump" ]; then
        echo "skipping metal-phone-home for kdump..."
        return 0
    fi

    local sqfs_store=/squashfs_management
    if [ "${metal_uri_scheme}" != "file" ]; then
        tmp1="${metal_uri_authority#//}" # Chop the double slash prefix
        tmp2="${tmp1%%/*}"                # Chop the trailing path
        uri_host="${tmp2%%:*}"            # Chop any port number
        if ping -c 5 "${uri_host}" > /dev/null 2>&1; then
            info "URI host ${uri_host} responds ..."
        else
            warn "Failed to ping URI host, ${uri_host:-UNDEFINED}, will retry later"
            return 1
        fi
    fi
    mkdir -pv $sqfs_store
    if mount -n -t xfs "/dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority}" $sqfs_store; then
        mkdir -pv "$sqfs_store/$live_dir"
        fetch_sqfs "$sqfs_store/$live_dir" "$sqfs_store/$live_dir"
        umount $sqfs_store
    else

        # No RAID mount, issue warning, delete mount-point and return
        metal_die "Failed to mount /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority} at $sqfs_store"
    fi
}

##############################################################################
## Pave
# Any disk caught in this function's scan will be wiped. Certain aspects are
# recoverable by experts, but only if no other function is called from this
# library (and no reformatting has occurred).
# This only targets disks that CRAY and its customers are interested in, specifically; RAID, SATA, NVME, and SAS devices/handles.
# NOTE: THIS NEVER WILL TARGET USB or VIRTUAL MEDIA!
# MAINTAINER NOTE DO NOT VOID THE AFOREMENTIONED STATEMENT!
# (these are the busses this scans for from `lsblk`).
pave() {
    if [ "$metal_nowipe" != 0 ]; then
        warn 'local storage device wipe [ safeguard ENABLED  ]'
        warn 'local storage devices will not be wiped.'
        echo 0 > /tmp/metalpave.done && return 0
    else
        warn 'local storage device wipe [ safeguard DISABLED ]'
    fi
    warn 'local storage device wipe commencing (USB devices are ignored)...'

    local doomed_disks
    local doomed_ceph_vgs='vg_name=~ceph*'
    local doomed_metal_vgs='vg_name=~metal*'

    # Select the span of devices we care about; RAID, SATA, NVME, and SAS devices/handles.
    doomed_disks=$(lsblk -l -o SIZE,NAME,TYPE,TRAN | grep -E '(raid|sata|nvme|sas)' | sort -u | awk '{print "/dev/"$2}' | tr '\n' ' ')
    [ -z "$doomed_disks" ] && echo 0 > /tmp/metalpave.done && return 0

    warn nothing can be done to stop this except one one thing...
    warn ...power this node off within the next 5 seconds to prevent any and all operations...
    while [ "${time_to_live:-5}" -gt 0 ]; do
        [ "${time_to_live}" = 2 ] && unit='second' || unit='seconds'
        sleep 1 && local time_to_live=$((${time_to_live:-5} - 1)) && echo "${time_to_live:-5} $unit"
    done

    # NUKES: these go in order from logical (e.g. LVM) -> block (e.g. block devices from lsblk) -> physical (e.g. RAID and other controller tertiary to their members).

    # NUKE LVMs
    for volume_group in $doomed_ceph_vgs $doomed_metal_vgs; do
        warn removing all volume groups of name \'$volume_group\' && vgremove -f --select $volume_group -y >/dev/null 2>&1 || warn no $volume_group volumes found
    done

    # NUKE BLOCKs
    warn local storage device wipe targeted devices: "$doomed_disks"
    for doomed_disk in $doomed_disks; do
        wipefs --all --force "$doomed_disk" 2> /dev/null
    done

    # NUKE RAIDs
    mdraid-cleanup >/dev/null 2>&1 # this is very noisy and useless to see but this call is needed.

    _trip_udev

    warn local storage disk wipe complete && echo 1 > /tmp/metalpave.done
}
