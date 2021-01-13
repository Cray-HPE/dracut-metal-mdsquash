#!/bin/sh

[ -z "${metal_debug:-0}" ] || set -x

# Load and execute with desired URL driver.
case "${metal_server:-}" in
    http:* | https:*)
        # use built-in driver for basic file/http/https url
        /sbin/initqueue --settled /sbin/metal-md-disks
        ;;
    file:device=*)
        #todo: add disk-mount support (metal.server=file:/var/www/filesystem.squashfs)
        #todo: mount given device, then strip URL so it's "normalized."
        # wait_for_dev /dev/disk/by-label/${metal_server#=*}
        warn "file:device=* is not yet implemented"
        ;;
    ''|file:*)
        # todo: anything before we call this?
        /sbin/initqueue --settled /sbin/metal-md-disks
        ;;
    *)
        info Unknown driver "$metal_server"
        ;;
esac
