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
# metal-genrules.sh
[ "${metal_debug:-0}" = 0 ] || set -x

command -v getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh

case "$(getarg root)" in 
    kdump)
        /sbin/initqueue --settled /sbin/metal-md-scan
        
        # Ensure nothing else in this script is invoked in this case.
        exit 0
        ;;
esac

command -v wait_for_dev > /dev/null 2>&1 || . /lib/dracut-lib.sh
command -v metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

# Load and execute with desired URL driver.
export metal_uri_scheme=${metal_server%%:*}
export metal_uri_authority=${metal_server#*:}

case "${metal_uri_scheme:-}" in
    file|http|https)
        wait_for_dev -n /dev/metal
        /sbin/initqueue --settled /sbin/metal-md-disks
        ;;
    s3)
        metal_die "s3-direct is not implemented, try http/https instead"
        ;;
    ftp)
        metal_die "insecure ftp is not implemented"
        ;;
    scp|sftp)
        metal_die "credential based transfer (scp and sftp) is not implemented, try http/https instead"
        ;;
    '')
        # Boot from block device.
        /sbin/initqueue --settled /sbin/metal-md-scan
        ;;
    *)
        warn "Unknown driver $metal_server; metal.server ignored/discarded"
        ;;
esac
