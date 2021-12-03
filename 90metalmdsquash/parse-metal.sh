#!/bin/sh
# Copyright 2021 Hewlett Packard Enterprise Development LP
# parse-metal.sh for metalmdsquash

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
