#!/bin/bash
# Copyright 2021 Hewlett Packard Enterprise Development LP
# parse-metal.sh for metalmdsquash

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
getargbool 0 metal.debug -d -y metal_debug && metal_debug=1

metal_disks=$(getargnum 2 1 10 metal.disks)
getargbool 0 metal.no-wipe -d -y metal_nowipe && metal_nowipe=1 || metal_nowipe=0
metal_overlay=$(getarg rd.live.overlay)
[ -z "${metal_overlay}" ] && metal_overlay=LABEL=ROOTRAID
metal_server=$(getarg metal.server=)

# if any of these are not present on the cmdline they should remain as null (and not = 0).
getargbool 0 metal.gcp-mode -d -y metal_gcp_mode && metal_gcp_mode=1
getargbool 0 metal.ipv4 -d -y metal_gcp_mode && metal_ipv4=1

export metal_debug
export metal_disks
export metal_nowipe
export metal_overlay
export metal_server
export metal_gcp_mode
export metal_ipv4
