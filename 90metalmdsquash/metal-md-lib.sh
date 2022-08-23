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
[ "${metal_debug:-0}" = 0 ] || set -x

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
command -v metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

# Honor and obey dmsquash parameters, if a user sets a different rd.live.dir on the cmdline then it
# should be reflected here as well.

# these use getargnum from /lib/dracut-lib.sh; <default> <min> <max>
metal_sqfs_size_end=$(getargnum 25 25 100 metal.sqfs-md-size)
overlay_size_end=$(getargnum 150 25 200 metal.oval-md-size)
auxillary_size_end=$(getargnum 150 0 200 metal.aux-md-size)

# The time (in seconds) for delaying the wipe once the wipe has been invoked.
metal_wipe_delay=$(getargnum 5 2 60 metal.wipe-delay)

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
# dracut defaults to squsahfs.img if undefined, we need to do the same for dracut-live to work.
squashfs_file=$(getarg rd.live.squashimg=)
[ -z "${squashfs_file}" ] && squashfs_file=squashfs.img
case ${metal_uri_authority} in
    *\?*)
        # In this case the URL has the filename; we'll save the file to whatever rd.live.squashimg is set to.
        squashfs_url="${metal_server}"
        ;;
    *)
        # In this case the URL does not have the filename.
        squashfs_url="${metal_server}/${squashfs_file}"
        :
        ;;
esac

# rootfallback may be empty, if it is then this block will ignore.
boot_fallback=$(getarg rootfallback=)
boot_drive_scheme=${boot_fallback%%=*}
[ -z "$boot_drive_scheme" ] && boot_drive_scheme=LABEL
boot_drive_authority=${boot_fallback#*=}
[ -z "$boot_drive_authority" ] && boot_drive_authority=BOOTRAID
case $boot_drive_scheme in
    PATH | path | UUID | uuid | LABEL | label)
        info "bootloader will be located on ${boot_drive_scheme}=${boot_drive_authority}"
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
        export sqfs_drive_scheme=${sqfs_drive_spec%%/*}
        export sqfs_drive_authority=${sqfs_drive_spec#*/}
        ;;
    live:*)
        sqfs_drive_url=${root#live:}
        sqfs_drive_spec=${sqfs_drive_url#*:}
        export sqfs_drive_scheme=${sqfs_drive_spec%%=*}
        export sqfs_drive_authority=${sqfs_drive_spec#*=}
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
    if [ -b /dev/md/SQFS ]; then
        echo 0 > /tmp/metalsqfsdisk.done && return
    fi

    # Loop through our disks and make our partitions needed for a squashFS storage:
    # - BOOTRAID : For fallback booting.
    # - SQFSRAID : For stowing squashFS images.
    local boot_raid_parts=''
    local sqfs_raid_parts=''
    for disk in "${md_disks[@]}"; do
    
        parted --wipesignatures -m --align=opt --ignore-busy -s "/dev/$disk" -- mklabel gpt \
            mkpart esp fat32 2048s 500MB set 1 esp on \
            mkpart primary xfs 500MB "${metal_sqfs_size_end}GB"
        _trip_udev

        # NVME partitions have a "p" to delimit the partition number.
        if [[ "$disk" =~ "nvme" ]]; then
            disk="${disk}p" 
        fi

        boot_raid_parts="$(trim $boot_raid_parts) /dev/${disk}1"
        sqfs_raid_parts="$(trim $sqfs_raid_parts) /dev/${disk}2"
    done

    # metadata=0.9 for boot files.
    mdadm --create /dev/md/BOOT --run --verbose --assume-clean --metadata=0.9 --level="$metal_mdlevel" $mdadm_raid_devices ${boot_raid_parts} || metal_die -b "Failed to make filesystem on /dev/md/BOOT"

    mdadm --create /dev/md/SQFS --run --verbose --assume-clean --metadata=1.2 --level="$metal_mdlevel" $mdadm_raid_devices ${sqfs_raid_parts} || metal_die -b "Failed to make filesystem on /dev/md/SQFS"

    _trip_udev
    mkfs.vfat -F32 -n "${boot_drive_authority}" /dev/md/BOOT || metal_die 'Failed to format bootraid.'

    # NOTE: DO NOT LABEL THE SQFS ARRAY HERE, or dracut may try to open it before we've populated it with artifacts.
    mkfs.xfs -f /dev/md/SQFS || metal_die 'Failed to format squashFS storage.'

    echo 1 > /tmp/metalsqfsdisk.done && info 'SquashFS storage is ready...'
}

##############################################################################
## Persistent OverlayFS
# Create the SquashFS Storage.
# Partition XFS 64bit.
make_raid_overlay() {

    _trip_udev
    if [ -b /dev/md/ROOT ]; then
        echo 0 > /tmp/metalovaldisk.done && return
    fi

    local oval_raid_parts=''
    local aux_raid_parts=''
    local oval_end="$((overlay_size_end + metal_sqfs_size_end))"
    local aux_end="$((auxillary_size_end + oval_end))"
    for disk in "${md_disks[@]}"; do
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary xfs "${metal_sqfs_size_end}GB" "${oval_end}GB"
        parted --wipesignatures --align=opt -m --ignore-busy -s "/dev/$disk" mkpart primary "${oval_end}GB" "${aux_end}GB"

        # NVME partitions have a "p" to delimit the partition number.
        if [[ "$disk" =~ "nvme" ]]; then
            disk="${disk}p" 
        fi

        oval_raid_parts="$(trim $oval_raid_parts) /dev/${disk}3"
        aux_raid_parts="$(trim $aux_raid_parts) /dev/${disk}4"
    done

    mdadm --create /dev/md/ROOT --assume-clean --run --verbose --metadata=1.2 --level="$metal_mdlevel" $mdadm_raid_devices ${oval_raid_parts} || metal_die -b "Failed to make filesystem on /dev/md/ROOT"
    mdadm --create /dev/md/AUX --assume-clean --run --verbose --metadata=1.2 --level='stripe' $mdadm_raid_devices ${aux_raid_parts} || metal_die -b "Failed to make filesystem on /dev/md/AUX"

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
    mkdir -pv ${mpoint}
    if ! mount -v -n -t xfs /dev/md/ROOT "$mpoint"; then

        # try shasta-1.3 formatting or die.
        mount -v -n -t ext4 /dev/md/ROOT "$mpoint" \
            || metal_die "Failed to mount ${oval_drive_authority} as xfs or ext4"
    fi

    # Create OverlayFS directories for dmsquash-live
    # See source-code for details: https://github.com/dracutdevs/dracut/blob/09a1e5afd2eaa7f8e9f3beaf8a48283357e7fea0/modules.d/90dmsquash-live/dmsquash-live-root.sh#L168-L169
    # Requires two directories; ovlwork, and overlay-$FSLABEL-$UUID (where FSLABEL and UUID are of the partition containing the squashFS image).
    [ -z "${metal_overlayfs_id}" ] && metal_overlayfs_id="$(_overlayFS_path_spec)"
    mkdir -v -m 0755 -p \
        "${mpoint}/${live_dir}/${metal_overlayfs_id}" \
        "${mpoint}/${live_dir}/${metal_overlayfs_id}/../ovlwork"
    echo 1 > /tmp/metalovalimg.done && info 'OverlayFS is ready ...'
    umount -v ${mpoint}
}

############################################```##################################
## SquashFS
# Gets the squashFS file from a URL endpoint or a local endpoint.
fetch_sqfs() {
    # TODO: Add md5 check - this may vary between Artifactory/bootstrap and s3/production artifacts at the present time.
    [ -f "$1/${squashfs_file}" ] && echo 0 > /tmp/metalsqfsimg.done && return
    [ -z "$metal_server" ] && warn 'No metal.server=, nothing to download or copy' && echo 0 > /tmp/metalsqfsimg.done && return

    # Remote file support; fetch the file.
    if [ "${metal_uri_scheme}" != "file" ]; then
        (
            set -e
            cd "$1"
            curl -f ${metal_ipv4:+-4} -o ${squashfs_file} "${squashfs_url}" > download.stdout 2> download.stderr
        ) || warn 'Failed to download ; may retry'

    # File support; copy the authority to tmp; tmp auto-clears on root-pivot.
    else
        metal_local_dir=${metal_uri_authority%%\?*}
        metal_local_url=${metal_server#*\?}
        metal_local_url_authority=${metal_local_url#*=}
        [ -z "$metal_local_url_authority" ] && metal_die "Missing LABEL=<FSLABEL> on $metal_server"

        # Mount read-only to prevent harm to the device; we literally just need to pull the files off it.
        mkdir -vp /tmp/source
        mount -v  -n -o ro -L "$metal_local_url_authority" /tmp/source || metal_die "Failed to mount $metal_local_url_authority from $metal_server"
        (
            set -e
            cd "$1"
            cp -pv "/tmp/source/${metal_local_dir#//}/${squashfs_file}" . && echo "copied ${squashfs_file} ... " > debug_log
        ) || warn 'Failed to copy ; may retry'
        umount -v /tmp/source
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

    local sqfs_store=/metal/squashfs
    local dhcp_retry=$(getargnum 1 1 1000000000 rd.net.dhcp.retry=)
    local dhcp_attempts=1
    if [ "${metal_uri_scheme}" != "file" ]; then
        tmp1="${metal_uri_authority#//}"  # Chop the double slash prefix
        tmp2="${tmp1%%/*}"                # Chop the trailing path
        uri_host="${tmp2%%:*}"            # Chop any port number
        
        # In some cases this module will arrive at this condition before dracut has attempted an ifup.
        while ! ping ${metal_ipv4:+-4} -c 5 "${uri_host}" > /dev/null 2>&1; do
            warn "Failed to ping URI host, ${uri_host:-UNDEFINED} ... (retry: $dhcp_attempts)"
            sleep 3
            
            # If we have retried enough times then the boot needs to fail.
            if [ $dhcp_attempts -ge $dhcp_retry ]; then
                metal_die 'Failed to obtain an IP address!'
            else
                for ip in $(getargs ip=); do 
                    nic=${ip%%:*}
                    protocol=${ip#*:}
                    case $protocol in
                        dhcp)
                            ifup $nic
                            dhcp_attempts=$((dhcp_attempts + 1))
                            ;;
                        *)
                            :
                            ;;
                    esac
                done
            fi
        done
        info "URI host ${uri_host} responds ... "
    fi
    mkdir -pv $sqfs_store
    if mount -v -n -t xfs /dev/md/SQFS $sqfs_store; then
        mkdir -pv "$sqfs_store/$live_dir"
        fetch_sqfs "$sqfs_store/$live_dir" || metal_die 'Failed to fetch squashFS into squashFS storage!'
        umount -v $sqfs_store
    else
        # No RAID mount, issue warning, delete mount-point and return
        metal_die "Failed to mount /dev/md/SQFS at $sqfs_store"
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
    local log="$METAL_DONE_FILE_PAVED.log"
    echo '${FUNCNAME[0]} called' >$log
    
    # If the done file already exists, do not modify it and do not touch anything.
    # Return 0 because the work was already done and we don't want to layer more runs of this atop
    # the original run.
    if [ -f "$METAL_DONE_FILE_PAVED" ]; then
        echo "${FUNCNAME[0]} already done" >>$log
        echo "wipe done file already exists ("$METAL_DONE_FILE_PAVED"); not wiping disks"
        return 0
    fi
    mount -v >>$log 2>&1
    lsblk >>$log 2>&1
    ls -l /dev/md* >>$log 2>&1
    ls -l /dev/sd* >>$log 2>&1
    ls -l /dev/nvme* >>$log 2>&1
    cat /proc/mdstat >>$log 2>&1
    if [ "$metal_nowipe" != 0 ]; then
        echo "${FUNCNAME[0]} skipped: metal.no-wipe=${metal_nowipe}" >>$log
        warn 'local storage device wipe [ safeguard: ENABLED  ]'
        warn 'local storage devices will not be wiped.'
        echo 0 > "$METAL_DONE_FILE_PAVED" && return 0
    else
        warn 'local storage device wipe [ safeguard: DISABLED ]'
    fi
    warn 'local storage device wipe commencing (USB devices are ignored) ...'

    local doomed_disks
    local doomed_ceph_vgs='vg_name=~ceph*'
    local doomed_metal_vgs='vg_name=~metal*'
    local vgfailure

    # Select the span of devices we care about; RAID, and all compatible transports.
    doomed_disks="$(lsblk -l -o SIZE,NAME,TYPE,TRAN | grep -E '(raid|'"$metal_transports"')' | sort -u | awk '{print "/dev/"$2}' | tr '\n' ' ' | sed 's/ *$//')"

    warn 'nothing can be done to stop this except one one thing ...'
    warn "... power this node off within the next [$metal_wipe_delay] seconds to prevent any and all operations ..."
    while [ "${metal_wipe_delay}" -ge 0 ]; do
        [ "${metal_wipe_delay}" = 2 ] && unit='second' || unit='seconds'
        sleep 1 && local metal_wipe_delay=$((${metal_wipe_delay} - 1)) && echo "${metal_wipe_delay} $unit"
    done

    #
    # NUKES: these go in order from logical (e.g. LVM) -> block (e.g. block devices from lsblk) -> physical (e.g. RAID and other controller tertiary to their members).
    #

    # NUKE LVMs
    vgscan >&2 && vgs >&2
    vgfailure=0
    for volume_group in $doomed_ceph_vgs $doomed_metal_vgs; do
        warn "removing all volume groups of name [${volume_group}]" && vgremove -f --select ${volume_group} -y >&2 || warn "no ${volume_group} volumes found"
        if [ "$(vgs --select $volume_group)" != '' ]; then
            warn "${volume_group} still exists, this is unexpected. Printing vgs table:"
            vgs >&2
            vgfailure=1
        fi
    done
    if [ ${vgfailure} -ne 0 ]; then
        warn 'Failed to remove all volume groups! Try rebooting this node again.'
        warn "If this persists, try running the manual wipe in the emergency shell and reboot again."
        warn "After trying the manual wipe, run 'echo b >/proc/sysrq-trigger' to reboot"
        metal_die "https://github.com/Cray-HPE/docs-csm/blob/main/operations/node_management/Wipe_NCN_Disks.md#basic-wipe"
    fi

    # NUKE BLOCKs
    warn "local storage device wipe targeted devices: [$doomed_disks]"
    for doomed_disk in $doomed_disks; do
        wipefs --all --force $doomed_disk* 2> /dev/null
    done

    # NUKE RAIDs
    mdraid-cleanup >/dev/null 2>&1 # this is very noisy and useless to see but this call is needed.

    _trip_udev

    warn 'local storage disk wipe complete' && echo 1 > "$METAL_DONE_FILE_PAVED"
    echo "${FUNCNAME[0]} done" >>$log
    mount -v >>$log 2>&1
    lsblk >>$log 2>&1
    ls -l /dev/md* >>$log 2>&1
    ls -l /dev/sd* >>$log 2>&1
    ls -l /dev/nvme* >>$log 2>&1
    cat /proc/mdstat >>$log 2>&1
}

##############################################################################
## metal_md_exit
# Conclude and exit the dracut init loop.
# Provide the expected devices to dmsquash-live
metal_md_exit() {
    [ ! -b /dev/md/SQFS ] && return 1
    xfs_admin -L "${sqfs_drive_authority}" /dev/md/SQFS
    ln -s null /dev/metal
}
