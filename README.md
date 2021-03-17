# 90metalmdsquash - mdraid management for squashFS image storage with persistent overlayFS

The Metal MDSquash dracut module lives in the initramFS, used during a server's boot. Within the initramFS, `metalmdsquash` does three things:
- It creates an mdraid array and sets up three partition
- It fetches a squashFS file from a given endpoint
- It creates a persistent overlayFS for the squashFS image 

> For more information on Dracut, the initramFS creation tool, see here: https://github.com/dracutdevs/dracut

Variable by customization arguments, the redundant storage will provision mirrored array across two "small" disks. This array
will contain 3 partitions; a partition for storing the fallback bootloader, another for storing squashFS images, and a final one for
storing persistent overlays.

> For information on partitioning and disks in Shasta, see [PARTITIONING](https://stash.us.cray.com/projects/MTL/repos/docs-csm-install/browse/104-NCN-PARTITIONING.md).

#### Table of Contents

- [Requirements](#requirements)
- [Usage](#usage)
- [URI Drivers](#uri-drivers)
- [Module Customization](#module-customization)
- [RootFS and the Persistent OverlayFS](#rootfs-and-the-persistent-overlayfs)

## Requirements

In order to use this dracut module, you need:

1. A local-attached-usb or remote server with a squashFS image.
2. Physical block devices must be installed in your blade(s).
3. Two physical disk of 0.5TiB or less (or the RAID must be overridden, see [module customization](#module-customization)

## Usage

Specify a local disk device for storing images, and the URL/endpoint to fetch images from.

```
metal.server=<URI> root=live:LABEL=SQFSRAID rd.live.squashimg=filesystem.squashfs
```

The above snippet is the minimal cmdline necessary for this module to function. Additional options 
are denoted throughout the [module customization](#module-customization) section.

## URI Drivers

The URI scheme, authority, and
path values will tell the module where to look for SquashFS. Only those parts of a URI are supported.

- file driver
    ```bash
    file:LABEL=MYUSB
    file:UUID=4e457dcf-df58-4460-86b4-4dbcd19f6fc7
    ```
- http or https driver
    ```bash
    http://api-gw-service/path/to/service/endpoint
    http://pit/
    http://10.100.101.111/some/local/server
    ```

Other drivers, such as native `s3`, `scp`, and `ftp` could be _added_.

These drivers schemes are all defined by the rule generator, [`metal-genrules.sh`](./metal-genrules.sh).

## Module Customization

**The assigned value denotes the default value when the option is omitted on the cmdline.**

### metal-mdsquash customizations

##### `metal.debug=0`
> Enables debug output, verbosely prints the creation of the RAIDs and fetching of the squashFS image.
> Set this to any non-zero to enable debugging.

##### `metal.disks=2`
> Specify the number of disks to use in the local mirror (RAID-1).


##### `metal.md-level=mirror`
> Change the level passed to mdadm for RAID creation, possible values are any value it takes. 
> Milaege varies, buyer beware this could dig a hole deeper.

##### `metal.no-wipe=0`
> If this is set to 1, then the existing partition table will remain untouched. No new partitons
> are created and no new RAIDs. Only set this if the current layout works, i.e. the client 
> already has the right partitions and a bootable ROM.

##### `metal.sqfs-md-size=100`
> Set the size for the new SQFS partition.
> Buyer beware this does not resize, this applies for new partitions.

### dmsquashlive customizations

reference: [dracut dmsquashlive cmdline](1)

##### `rd.live.dir=LiveOS`
> Specify the dir to use within the squashFS reserved area.

##### `root=live:CDLABEL=SQFSRAID`
> Specify the FSlabel of the block device to use for the SQFS storage. This could be an existing RAID or non-RAIDed device.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved with a new mirror array.
> Can also be of UUID or 

##### `rd.live.overlay=LABEL=ROOTRAID`
> Specify the FSlabel of the block device to use for persistent storage.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved.
> If this is specified, then rd.live.overlay=$newlabel must also be specified.

##### `rd.live.overlay.readonly=0`
> Make the persistent overlayFS read-only.

##### `rd.live.overlay.reset=0`
> Reset the persistent overlayFS, regardless if it is read-only.
> Note: If this is 1, but `metal.no-wipe=1` too then this will not remake the persistent image file
> but dmsquash-live may still reset the contents. The overlay just won't be
> reformatted `metal.no-wipe=1`.

##### `rd.live.overlay.size=204800`
> Specify the size of the overlay in MB.

##### `rd.live.squashimg=filesystem.squashfs`
> Specify the filename to refer to download.

### dracut : standard customizations

notereference: [dracut standard cmdline](2)

##### `rootfallback=LABEL=BOOTRAID`
> This the label for the partition to be used for a fallback bootloader.

## RootFS and the Persistent OverlayFS

### What is a Persistent Overlay?

The idea of persistence is that changes _persist_ across reboots, when the state of the machine
changes it preserves information.

## Feature Toggles

Metal squashFS URL Dracut module has a few feature toggles, by default it is recommended to leave
them alone unless you must change them for your environment.

### Toggling Persistence

Disable the overlayFS entirely by setting `rd.live.overlay=0`, this will cause a temporary overlay
to be created that exists in memory. A prompt may appear during boot to acknowledge the RAM overlayFS.

To disable it entirely, delete all `rd.live.overlay.*` options.

### Toggling Read-Only OverlayFS

Setting `rd.live.readonly=1` will cause the next boot's persistent overlayFS to be mounted
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
`rd.live.overlay.reset=1`.

The OverlayFS is reset by recreating the image file if it doesn't exist, and then by wiping the image
file if it does exist. The wipe is controlled by dracut-native (dmsquash-live), the creation of
the image file is handled by this dracut module (metal-squashfs-url-dracut).

[1]: https://github.com/dracutdevs/dracut/blob/master/dracut.cmdline.7.asc#booting-live-images
[2]: https://github.com/dracutdevs/dracut/blob/master/dracut.cmdline.7.asc#standard
