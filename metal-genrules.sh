#!/bin/sh
# Copyright 2021 Hewlett Packard Enterprise Development LP
# metal-genrules.sh for metalmdsquash

[ -z "${metal_debug:-0}" ] || set -x

# Load and execute with desired URL driver.
case "${metal_server:-}" in
    ''|file:*|http:*|https:*)
        # use built-in driver for basic file/http/https url
        /sbin/initqueue --settled /sbin/metal-md-disks
        ;;
    s3:*)
        warn s3-direct is not implemented, try http/https instead
        ;;
    ftp:*)
        warn insecure ftp is not implemented
        ;;
    scp:*|sftp:*)
        warn credential based transfer (scp and sftp) is not implemented, try http/https instead
        ;;
    *)
        info Unknown driver "$metal_server"; metal.server ignored/discarded
        ;;
esac
