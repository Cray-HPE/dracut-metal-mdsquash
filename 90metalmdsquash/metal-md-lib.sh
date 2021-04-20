#!/bin/bash

PATH=/usr/sbin:/usr/bin:/sbin:/bin

[ "${metal_debug:-0}" = 1 ] && echo "$@" && set -x

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

# Honor and obey dmsquash parameters, if a user sets a different rd.live.dir on the cmdline then it
# should be reflected here as well.
live_dir=$(getarg rd.live.dir -d live_dir)
[ -z "${live_dir}" ] && live_dir="LiveOS"

initrd=$(getarg initrd=)
[ -z "${initrd}" ] && initrd="initrd.img.xz"

# these use getargnum from /lib/dracut-lib.sh; <default> <min> <max>
metal_sqfsmdsize=$(getargnum 25 25 100 metal.sqfs-md-size)
overlay_size=$(getargnum 150 25 200 metal.oval-md-size)
auxillary_size=$(getargnum 150 0 200 metal.aux-md-size)
metal_mdlevel=$(getarg metal.md-level=)
[ -z "${metal_mdlevel}" ] && metal_mdlevel=mirror

squashfs_file=$(getarg rd.live.squashimg=)
[ -z "${squashfs_file}" ] && squashfs_file=filesystem.squashfs
[ "${squashfs_file}" = '.squashfs' ] && squashfs_file=filesystem.squashfs
metal_squashfsurl="${metal_server%%/}/${squashfs_file}"
IFS=':' read -ra ADDR <<< "$metal_squashfsurl"
metal_uri_scheme=${metal_squashfsurl%%:*}
metal_authority_path=${metal_squashfsurl#*:}
if [ -z "${metal_uri_scheme}" ] || [ -z "${metal_authority_path}" ]; then
    metal_die "Failed to parse the scheme, authority, and path for URI ${metal_squashfsurl}"
fi

# Grub / Fallback.
boot_fallback=$(getarg rootfallback=)
boot_drive_scheme=${boot_fallback%%=*}
boot_drive_authority=${boot_fallback#*=}
case $boot_drive_scheme in
    PATH | path | UUID | uuid | LABEL | label)
        info "bootloader will be located on  ${boot_drive_scheme}=${boot_drive_authority}"
        ;;
    '')
        # no-op; drive disabled
        :
        ;;
    *)
        warn "Unsupported boot-drive-scheme ${boot_drive_scheme}"
        warn "Supported schemes: PATH, UUID, and LABEL (upper and lower cases)"
        exit 1
        ;;
esac

root=$(getarg root)
# SquashFS Storage
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
        warn "No root; root needed"
        exit 1
        ;;
    *)
        warn "alien root! unrecognized root= parameter: root=${root}"
        ;;
esac
[ "${sqfs_drive_scheme}" = 'CDLABEL' ] || sqfs_drive_scheme=LABEL

# Export SquashFS drive information to dracut environment.
case $sqfs_drive_scheme in
    PATH | path | UUID | uuid | LABEL | label)
        info "SquashFS file is on ${sqfs_drive_scheme}=${sqfs_drive_authority}"
        ;;
    *)
        warn "Unsupported sqfs-drive-scheme ${sqfs_drive_scheme}"
        warn "Supported schemes: PATH, UUID, and LABEL"
        exit 1
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

_trip_udev() {
    udevadm settle >&2
}

_overlayFS_path_spec() {
    echo "overlay-${sqfs_drive_authority}-$(blkid -s UUID -o value /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority})"
}

##############################################################################
## Die.
metal_die() {
    echo "metal_die: $*"
    sleep 30 # Leave time for console/log buffers to catch up.
    die
}

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
            mkpart primary xfs 500MB "${metal_sqfsmdsize}GB"
        _trip_udev
        boot_raid_parts="$(trim $boot_raid_parts) /dev/${disk}1"
        sqfs_raid_parts="$(trim $sqfs_raid_parts) /dev/${disk}2"
    done
    # metadata=0.9 for boot files.
    mdadm --create /dev/md/BOOT --run --verbose --assume-clean --metadata=0.9 --level="$metal_mdlevel" --raid-devices=$metal_disks ${boot_raid_parts} || metal_die "Failed to make filesystem on /dev/md/BOOT"
    mdadm --create /dev/md/SQFS --run --verbose --assume-clean --metadata=1.2 --level="$metal_mdlevel" --raid-devices=$metal_disks ${sqfs_raid_parts} || metal_die "Failed to make filesystem on /dev/md/SQFS"

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
    local oval_end="$((overlay_size + metal_sqfsmdsize))"
    local aux_end="$((auxillary_size + oval_end))"
    for disk in $md_disks; do
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary xfs "${metal_sqfsmdsize}GB" "${oval_end}GB"
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary "${oval_end}GB" "${aux_end}GB"
        oval_raid_parts="$(trim $oval_raid_parts) /dev/${disk}3" # FIXME: Find partition number vs hard code.
        aux_raid_parts="$(trim $aux_raid_parts) /dev/${disk}4"
    done
    mdadm --create /dev/md/ROOT --assume-clean --run --verbose --metadata=1.2 --level="$metal_mdlevel" --raid-devices=$metal_disks ${oval_raid_parts} || metal_die "Failed to make filesystem on /dev/md/ROOT"
    mdadm --create /dev/md/AUX --assume-clean --run --verbose --metadata=1.2 --level="$metal_mdlevel" --raid-devices=$metal_disks ${aux_raid_parts} || metal_die "Failed to make filesystem on /dev/md/AUX"

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
    if [ "${metal_uri_scheme}" != "file" ]; then
        (
            set -e
            cd "$1"
            curl -O "${metal_squashfsurl}" > /dev/null 2>&1 && info "${squashfs_file} downloaded  ... "
            curl -O "${metal_server}/kernel" > /dev/null 2>&1 && info 'grabbed the kernel it rode in on ... '
            curl -O "${metal_server}/${initrd}" > /dev/null 2>&1 && info 'and its initrd ... '
        ) || warn 'Failed to download ; may retry'
    else
        # File support; copy the authority to tmp; tmp auto-clears on root-pivot.
        mkdir -vp /tmp/source

        # Mount read-only to prevent harm to the device; we literally just need to pull the files off it.
        mount -n -o ro "/dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority}" /tmp/source
        (
            set -e
            cd "$1"
            cp -pv "/tmp/source/${metal_squashfsurl#//}" . && info "copied ${squashfs_file} ... "
            cp -pv "/tmp/source/${metal_squashfsurl#//}/kernel" . && info 'grabbed the kernel we rode in on ... '
            cp -pv "/tmp/source/${metal_squashfsurl#//}${initrd}" . && info 'and its initrd ... '
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
    if [ $root = "kdump" ]; then
    echo "skipping metal-phone-home for kdump..."
    exit 0
    fi

    local sqfs_store=/squashfs_management
    if [ "${metal_uri_scheme}" != "file" ]; then
        tmp1="${metal_authority_path#//}" # Chop the double slash prefix
        tmp2="${tmp1%%/*}"                # Chop the trailing path
        uri_host="${tmp2%%:*}"            # Chop any port number
        if ping -c 5 "${uri_host}" > /dev/null 2>&1; then
            info "URI host ${uri_host} responds ..."
        else
            info "Failed to ping URI host, ${uri_host}, will retry later"
            return 1
        fi
    fi
    mkdir -pv $sqfs_store
    if mount -n -t xfs "/dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority}" $sqfs_store; then
        mkdir -pv "$sqfs_store/$live_dir"
        fetch_sqfs "$sqfs_store/$live_dir" "$sqfs_store/$live_dir"
        umount $sqfs_store
    else

        # No RAID mount, issue warning, delete mount point and return
        warn "Failed to mount /dev/disk/by-${sqfs_drive_scheme,,}/${sqfs_drive_authority} at $sqfs_store"
        rmdir $sqfs_store
        return 1
    fi
}

##############################################################################
## Pave
# Any disk caught in this functions view will be paved in preparation for use.
# This only targets disks that CRAY is interested in, specifically RAID, SATA, NVME
# (these are the busses this scans for from `lsblk`).
pave() {

    local doomed_disks
    local doomed_vgs='vg_name=~ceph*'
    local doomed_metal_vgs='vg_name=~aux*'

    # Select the span of devices we care about; RAID, SATA, and NVME devices/handles.
    doomed_disks=$(lsblk -l -o SIZE,NAME,TYPE,TRAN | grep -E '(raid|sata|nvme|sas)' | sort -u | awk '{print "/dev/"$2}' | tr '\n' ' ')
    [ -z "$doomed_disks" ] && echo 0 > /tmp/metalpave.done && return 0

    info nothing can be done to stop this except one one thing...
    info ...power this node off within the next 5 seconds to prevent any and all operations...
    while [ "${time_to_live:-5}" -gt 0 ]; do
        sleep 1 && local time_to_live=$((${time_to_live:-5} - 1)) && info "${time_to_live:-5}"
    done

    # NUKES: these go in order from logical -> block -> physical.

    # NUKE LVMs
    info removing all ceph volume groups of $doomed_vgs && vgremove -f --select $doomed_vgs || info 'no ceph volumes'
    info removing all metal volume groups of $doomed_metal_vgs && vgremove -f --select $doomed_metal_vgs || info 'no metal volumes'

    # NUKE BLOCKs
    info wiping doomed raids and block-devices: "$doomed_disks"
    for doomed_disk in $doomed_disks; do
        wipefs --all --force "$doomed_disk" 2> /dev/null || info failed to wipe doomed disk
    done

    # NUKE RAIDs
    mdraid-cleanup >/dev/null 2>&1 # this is very noisy and useless to see but this call is needed.

    _trip_udev

    info disk cleanslate achieved && echo 1 > /tmp/metalpave.done
}
