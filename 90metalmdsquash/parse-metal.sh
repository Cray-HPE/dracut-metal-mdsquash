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
# parse-metal.sh

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
getargbool 0 metal.debug -d -y metal_debug && metal_debug=1
[ "${metal_debug:-0}" = 0 ] || set -x

metal_disks=$(getargnum 2 1 10 metal.disks)
getargbool 0 metal.no-wipe -d -y metal_nowipe && metal_nowipe=1 || metal_nowipe=0
metal_overlay=$(getarg rd.live.overlay)
[ -z "${metal_overlay}" ] && metal_overlay=LABEL=ROOTRAID
metal_server=$(getarg metal.server=)

# For ${:+} BASH substitution to work, the value must be null or unset (0 != null in BASH)
getargbool 0 metal.ipv4 -d -y metal_ipv4 && metal_ipv4=1
[ "${metal_ipv4}" = 0 ] && metal_ipv4=''

export metal_debug
export metal_disks
export metal_nowipe
export metal_overlay
export metal_server
export metal_ipv4
