Metal MDSquash Module
===============

This module fetches a squashFS file onto a local disk array, and pairs it with a persistent storage 
image overlay.

- The SquashFS file can be fetched remotely, or from another local storage device (i.e. attached
USB stick for recovery or triage)
- The (optional) persistent storage image, is a simple file formatted with XFS

For information on partitioning and disks in Shasta, see [PARTITIONING](https://stash.us.cray.com/projects/MTL/repos/docs-csm-install/browse/104-NCN-PARTITIONING.md).

## Requirements

In order to use this dracut module to boot a non-compute node, you need:

1. A local-attached-usb or remote server with a squashFS image.
2. Physical block devices must be installed in your blade(s).

## Usage

This module works in conjunction with the native dmsquash-live module, tell your node
where to fetch its image from and where to boot from.

```
root=live:LABEL=<sqfspartition> metal.server=<URI>
```

### <URI>

This value is interpreted based upon the URI scheme, authority, and
path values. Only those parts of a URI are supported.

The following URI schemes are supported:

	- file
	- http

### The file URI

> This currently does not mount a device, it expects the file to be available to the
> initrd. This may be useful for virtual, but is not useful for metal at this time.

If the file URI scheme is specified it is assumed that what follows
is a path to the location of the squashfs in the boot image. Example:

	file:/path/to/squashfs

### The http URI

If the http URI scheme is specified, the authority and path for the
squashfs image to download:

Example:

	http://api-gateway-nmn.local/path/to/service/endpoint
	http://spit/file

### What is a Persistent Overlay?

The idea of persistence is that changes _persist_ across reboots, when the state of the machine
changes it preserves information.

# Feature Toggles

Metal squashFS URL Dracut module has a few feature toggles, by default it is recommeneded to leave
them alone unless you must change them for your environment.

### Toggling Persistence

Disable the overlayFS entirely by setting `rd.live.overlay=0`, this will cause a temporary overlay
to be created that exists in memory. A prompt may appear during boot to acknowledge the RAM overlayFS.

To disable it entirely, delete all `rd.live.overlay.*` options.

### Toggling Read-Only OverlayFS

Setting _rd.live.readonly=1_ will cause the next boot's persistent overlayFS to be mounted 
as read-only. This has a different convention in overlayFS and will look differently on your
system pending certain toggles:

- either an
    additional, non-persistent, writable snapshot overlay will be
    stacked over a read-only snapshot, /dev/mapper/live-ro, of the
    base filesystem with the persistent overlay, 
- or a read-only loop
    device, in the case of a writable rootfs.img,
- **(default)** or an OverlayFS
    mount will use the persistent overlay directory linked at
    /run/overlayfs-r as an additional lower layer along with the base
    root filesystem and apply a transient, writable upper directory
    overlay, in order to complete the booted root filesystem.

### Toggling Resetting the Persistent OverlayFS on Booot

To cleanly reset the overlayFS, reboot the node with this kernel option:
_`rd.live.overlay.reset=1`_

The OverlayFS is reset by recreating the image file if it doesn't exist, and then by wiping the image
file if it does exist. The wipe is controlled by dracut-native (dmsquash-live), the creation of 
the image file is handled by this dracut module (metal-squashfs-url-dracut).

# Visual References

### Persistent OverlayFS

Dmsquash-live provides persistence to the booted node. This module supplies dmsquash-live with the
necessary information to setup:
- The rootfs (squashFS  and the array it sits on)
- The overlayFS (persistent on-disk overlay filesystem)

The two parts used togther provide a readonly rootFS and a working persistence area.

The persistent folders shown below, are "exclusive-ored" against the lowerdir of the OS, meaning these
are applied and preserved without being in the image.:
```bash
ncn-m001:/run/overlayfs # ls -l
total 0
drwxr-xr-x 8 root root 290 Oct 15 22:41 etc
drwxr-xr-x 3 root root  18 Oct 15 22:41 home
drwx------ 3 root root  39 Oct 13 16:53 root
drwxr-xr-x 3 root root  18 Oct  5 19:16 srv
drwxrwxrwt 2 root root  85 Oct 16 14:50 tmp
drwxr-xr-x 8 root root  76 Oct 13 16:52 var
```

# Module Customization
> **The assigned value to each one denotes the default value.**

`metal.server=http://spit/`
> The URL for the SquashFS filesystem we want to download.
> Note that iso-scan/filename=filesystem.squashfs and rd.live.squashimg=filesystem.squashfs must
> be set as well to denote which file to fetch. Otherwise a default filename of squashfs.img is
> chosen per [kiwi's default rd.live.squashimg param](https://manpages.debian.org/testing/dracut-core/dracut.cmdline.7.en.html#Booting_live_images).

`metal.debug=0`
> Enables debug output, verbosely prints the creation of the RAIDs and fetching of the squashFS image.
> Set this to any non-zero to enable debugging.

`metal.disks=2`
> Specify the number of disks to use in the local mirror (RAID-1).

`metal.no-wipe=0`
> If this is set to 1, then the existing partition table will remain untouched. No new partitons
> are created and no new RAIDs. Only set this if the current layout works, i.e. the client 
> already has the right partitions and a bootable ROM.
 
```bash
# Upgrades can and sould set this - if the expected filesystems do not exist then this should be set to 0.
metal.no-wipe=1  <- SAFETY: Do not format, invoke mdadm, or partition anything.
metal.no-wipe=0  <- DEFAULT: run normally; make filesystems and RAID devices if not found.
metal.no-wipe=-1 <- Force a wipe of the RAIDs even if they exist.
```

#### Experimental Metal Kernel Options

These exist because they shouldn't be hardcodes, but they may be expanded for usage in the future.
You, developer, may use these to experiment or flex the installer to your will.
However, STRONGLY recommended to NOT set these.

`metal.md-level=mirror`
> Change the level passed to mdadm for RAID creation, possible values are any value it takes. 
> Milaege varies, buyer beware this could dig a hole deeper.


#### Kernel parameters shared between dmsquash-live and metalsquashfsurl.

> See all available options here: https://manpages.debian.org/testing/dracut-core/dracut.cmdline.7.en.html#Booting_live_images

>`root=live:CDLABEL=SQFSRAID`
> Specify the FSlabel of the block device to use for the SQFS storage. This could be an existing RAID or non-RAIDed device.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved with a new mirror array.
> Can also be of UUID or 

`rd.live.overlay=LABEL=ROOTRAID`
> Specify the FSlabel of the block device to use for persistent storage.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved.
> If this is specified, then rd.live.overlay=$newlabel must also be specified.

`rd.live.overlay.size=204800`
> Specify the size of the overlay in MB.

`rd.live.overlay.reset=0`
> Reset the persistent overlayFS, regardless if it is read-only.
> Note: If this is 1, but `metal.no-wipe=1` too then this will not remake the persistent image file
> but dmsquash-live may still reset the contents. The overlay just won't be
> reformatted `metal.no-wipe=1`.

`rd.live.overlay.readonly=0`
> Make the persistent overlayFS read-only.

`rd.live.dir=LiveOS`
> Specify the dir to use within the squashFS reserved area.

`rd.live.squashimg=filesystem.squashfs`
> Specify the filename to refer to download.
