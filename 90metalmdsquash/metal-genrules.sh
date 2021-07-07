#!/bin/sh
# Copyright 2021 Hewlett Packard Enterprise Development LP
# metal-genrules.sh for metalmdsquash
type metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

[ -z "${metal_debug:-0}" ] || set -x

# Load and execute with desired URL driver.
case "${metal_server:-}" in
    ''|file:*|http:*|https:*)
        # use built-in driver for basic file/http/https url
        /sbin/initqueue --settled /sbin/metal-md-disks
        ;;
    s3:*)
        metal_die s3-direct is not implemented, try http/https instead
        ;;
    ftp:*)
        metal_die insecure ftp is not implemented
        ;;
    scp:*|sftp:*)
        metal_die "credential based transfer (scp and sftp) is not implemented, try http/https instead"
        ;;
    *)
        warn Unknown driver "$metal_server"; metal.server ignored/discarded
        ;;
esac
