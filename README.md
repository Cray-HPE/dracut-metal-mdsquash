<a name="metal-90mdsquash---redundant-squashfs-and-overlayfs-storage"></a>
# METAL 90mdsquash - redundant squashFS and overlayFS storage

The Metal MDSquash dracut module lives in the initramFS, used during a server's boot. Within the initramFS, `metalmdsquash` does three things:
- It creates an mdraid array and sets up three partition
- It fetches a squashFS file from a given endpoint
- It creates a persistent overlayFS for the squashFS image
- Lastly, an LVM is created on the final partition for cloud-init and other high-level hand-off

> For more information on Dracut, the initramFS creation tool, see here: https://github.com/dracutdevs/dracut

Variable by customization arguments, the redundant storage will provision mirrored array across two "small" disks. This array
will contain 3 partitions; a partition for storing the fallback bootloader, another for storing squashFS images, and a final one for
storing persistent overlays.

> For information on partitioning and disks in Shasta, see [NCN Partitioning](https://stash.us.cray.com/projects/MTL/repos/docs-csm-install/browse/104-NCN-PARTITIONING.md).

<a name="table-of-contents"></a>
#### Table of Contents

* [METAL 90mdsquash - redundant squashFS and overlayFS storage](README.md#metal-90mdsquash---redundant-squashfs-and-overlayfs-storage)
  * [Table of Contents](README.md#table-of-contents)
  * [Requirements](README.md#requirements)
  * [Usage](README.md#usage)
  * [URI Drivers](README.md#uri-drivers)
* [Parameters](README.md#parameters)
  * [Kernel Parameters](README.md#kernel-parameters)
    * [metal-mdsquash customizations](README.md#metal-mdsquash-customizations)
      * [`metal.debug`](README.md#metaldebug)
      * [`metal.disks`](README.md#metaldisks)
      * [`metal.md-level`](README.md#metalmd-level)
      * [`metal.no-wipe`](README.md#metalno-wipe)
      * [`metal.ipv4`](README.md#metalipv4)
      * [`metal.sqfs-md-size`](README.md#metalsqfs-md-size)
      * [`metal.oval-md-size`](README.md#metaloval-md-size)
      * [`metal.aux-md-size`](README.md#metalaux-md-size)
    * [dmsquashlive customizations](README.md#dmsquashlive-customizations)
      * [`rd.live.dir`](README.md#`rdlivedir`)
      * [`root`](README.md#`root`)
      * [`rd.live.overlay`](README.md#`rdliveoverlay`)
      * [`rd.live.overlay.readonly`](README.md#`rdliveoverlayreadonly`)
      * [`rd.live.overlay.reset`](README.md#`rdliveoverlayreset`)
      * [`rd.live.overlay.size`](README.md#`rdliveoverlaysize`)
      * [`rd.live.squashimg`](README.md#`rdlivesquashimg`)
    * [dracut : standard customizations](README.md#dracut--standard-customizations)
      * [`rootfallback`](README.md#`rootfallback`)
  * [Required Parameters](README.md#required-parameters)
    * [`metal.server=http://pit/$hostname`](README.md#metalserver)
* [RootFS and the Persistent OverlayFS](README.md#rootfs-and-the-persistent-overlayfs)
  * [What is a Persistent Overlay?](README.md#what-is-a-persistent-overlay)
  * [Feature Toggles](README.md#feature-toggles)
    * [Toggling Persistence](README.md#toggling-persistence)
    * [Toggling Read-Only OverlayFS](README.md#toggling-read-only-overlayfs)
    * [Toggling Resetting the Persistent OverlayFS on Boot](README.md#toggling-resetting-the-persistent-overlayfs-on-boot)


<a name="requirements"></a>
## Requirements

In order to use this dracut module, you need:

1. A local-attached-usb or remote server with a squashFS image.
2. Physical block devices must be installed in your blade(s).
3. Two physical disk of 0.5TiB or less (or the RAID must be overridden, see [module customization](#module-customization)

<a name="usage"></a>
## Usage

Specify a local disk device for storing images, and the URL/endpoint to fetch images from on the kernel commandline (e.g. via `grub.cfg`, or an iPXE script).

```
metal.server=<URI> root=live:LABEL=SQFSRAID rd.live.squashimg=filesystem.squashfs
```

The above snippet is the minimal cmdline necessary for this module to function. Additional options 
are denoted throughout the [module customization](#parameters) section.

<a name="uri-drivers"></a>
## URI Drivers

The URI scheme, authority, and
path values will tell the module where to look for SquashFS. Only those parts of a URI are supported.

- file driver
    ```bash
    # Example: Load from another USB stick on the node.
    file://mydir?LABEL=MYUSB
    # Example: load a file from the root of an attached disk with the label SQFSRAID
    file://?LABEL=SQFSRAID
    # Example: load a file from a PIT recovery USB.
    file://ephemeral/data/ceph/?LABEL=PITDATA
    ```
- http or https driver
    ```bash
    http://api-gw-service/path/to/service/endpoint
    http://pit/
    http://10.100.101.111/some/local/server
    ```

Other drivers, such as native `s3`, `scp`, and `ftp` could be _added_.

These drivers schemes are all defined by the rule generator, [`metal-genrules.sh`](./90metalmdsquash/metal-genrules.sh).

<a name="parameters"></a>
# Parameters

**The assigned value denotes the default value when the option is omitted on the cmdline.**

<a name="kernel-parameters"></a>
## Kernel Parameters

<a name="metal-mdsquash-customizations"></a>
### metal-mdsquash customizations

<a name="metaldebug"></a>
##### `metal.debug`
> - `default: 0`
> 
> Set `metal.debug=1` to enable debug output from only metal modules. This will verbosely print the creation of the RAIDs and fetching of the squashFS image. **This effectively runs all dracut-metal code with `set -x`**, while leaving the rest of dracut to its own debug level.

<a name="metaldisks"></a>
##### `metal.disks`
> - `default: 2`
> 
> Specify the number of disks to use in the local RAID (see [`metal.md-level`](README.md#metalmd-level) for changing the RAID type).

<a name="metalmd-level"></a>
##### `metal.md-level`
> - `default: mirror`
> 
> Change the level passed to mdadm for RAID creation, possible values are any value it takes. 
> Milaege varies, buyer beware this could dig a hole deeper.

> **`NOTE**: When `metal.disks=1` is set, only mirror and stripe will work.


<a name="metalno-wipe"></a>
##### `metal.no-wipe`
> - `default: 0`
> 
> If this is set to `metal.no-wipe=1`, then all destructive behavior is disabled. The metal modules will either use what they find or make 0 changes during boots. This is insurance, it should not be required. This is helpful for development, or for admins tracking old and new nodes.


<a name="metalipv4"></a>
##### `metal.ipv4`
> - `default: 1`
>
> By default, metal-dracut will use IPv4 to resolve the deployment server for the initial call-to-home and when downloading artifacts regardless if IPv6 networking is present in the environment. To disable this constraint, simply set `metal.ipv4=0` in the cmdline. Setting this to `0` will enable all `ping` and `curl` calls for calling-home and downloading artifacts to use **either** IPv6 or IPv4 on their own accord (e.g. if IPv6 exists, then `ping` and `curl` will prefer to use it by default). Presumably if IPv6 is desired and exists, then IPv6 DHCP/DNS and general TCP/IP connectivity is working.
> Lastly, if IPv6 does not exist then toggling this value to `0` has no effect.


<a name="metalsqfs-md-size"></a>
##### `metal.sqfs-md-size`
> - default: `25`
> - Unit: Gigabytes
> 
> Set the size for the new SQFS partition.
> Buyer beware this does not resize, this applies for new partitions.


<a name="metaloval-md-size"></a>
##### `metal.oval-md-size`
> - default: `150`
> - Unit: Gigabytes
> 
> Set the size for the new SQFS partition.
> Buyer beware this does not resize, this applies for new partitions.


<a name="metalaux-md-size"></a>
##### `metal.aux-md-size`
> - default: `150`
> - Unit: Gigabytes
>
> Set the size for the new SQFS partition.
> Buyer beware this does not resize, this applies for new partitions.


<a name="dmsquashlive-customizations"></a>
### dmsquashlive customizations

reference: [dracut dmsquashlive cmdline](1)


<a name="rdlivedir"></a>
##### `rd.live.dir`
> - `default: LiveOS`
> 
> Name of the directory store and load the artifacts from. Changing this value will affect metal and native-dracut.

<a name="root"></a>
##### `root`
> - `default: live:LABEL=SQFSRAID`
> 
> Specify the FSlabel of the block device to use for the SQFS storage. This could be an existing RAID or non-RAIDed device.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved with a new mirror array.
> Can also be of UUID or 

<a name="rdliveoverlay"></a>
##### `rd.live.overlay`
> - `default: LABEL=ROOTRAID`
> 
> Specify the FSlabel of the block device to use for persistent storage.
> If a label is not found in `/dev/disk/by-label/*`, then the os-disks are paved.
> If this is specified, then rd.live.overlay=$newlabel must also be specified.

<a name="rdliveoverlay.readonly"></a>
##### `rd.live.overlay.readonly`
> - `default: 0`
> 
> Make the persistent overlayFS read-only.

<a name="rdliveoverlayreset"></a>
##### `rd.live.overlay.reset`
> - `default: 0`
> 
> Reset the persistent overlayFS, regardless if it is read-only.
> On the **next** boot the overlayFS will clear itself, it will continue to clear itself every
> reboot until this is unset. This does not remake the RAID, this remakes the OverlayFS. Metal only
> provides the underlying array, and the parent directory structure necessary for an OverlayFS to detect the array as compatible.

<a name="rdliveoverlaysize"></a>
##### `rd.live.overlay.size`
> - `default: 204800`
> 
> Specify the size of the overlay in MB.

<a name="rdlivesquashimg"></a>
##### `rd.live.squashimg`
> - `default: filesystem.squashfs`
> 
> Specify the filename to refer to download.

<a name="dracut--standard-customizations"></a>
### dracut : standard customizations

notereference: [dracut standard cmdline](2)

<a name="rootfallback"></a>
##### `rootfallback`
> - `default: LABEL=BOOTRAID`
> 
> This the label for the partition to be used for a fallback bootloader.

<a name="required-parameters"></a>
## Required Parameters

The following parameters are required for this module to work, however they belong to the native dracut space.

> See [`module-setup.sh`](./90metalmdsquash/module-setup.sh) for the full list of module and driver dependencies.

<a name="metal.server"></a>
##### `metal.server`

> The endpoint to fetch artifacts from. Can be any protocol defined in [`metal-genrules.sh`](./90metalmdsquash/metal-genrules.sh).
>
> **NOTE**: Omitting this value entirely will disable the (re)build function of this dracut module.

<a name="rootfs-and-the-persistent-overlayfs"></a>
# RootFS and the Persistent OverlayFS


<a name="what-is-a-persistent-overlay"></a>
### What is a Persistent Overlay?

The idea of persistence is that changes _persist_ across reboots, when the state of the machine
changes it preserves information.


<a name="feature-toggles"></a>
## Feature Toggles

Metal squashFS URL Dracut module has a few feature toggles, by default it is recommended to leave
them alone unless you must change them for your environment.


<a name="toggling-persistence"></a>
### Toggling Persistence

Disable the overlayFS entirely by setting `rd.live.overlay=0`, this will cause a temporary overlay
to be created that exists in memory. A prompt may appear during boot to acknowledge the RAM overlayFS.

To disable it entirely, delete all `rd.live.overlay.*` options.

<a name="toggling-read-only-overlayfs"></a>
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


<a name="toggling-resetting-the-persistent-overlayfs-on-boot"></a>
### Toggling Resetting the Persistent OverlayFS on Boot

To cleanly reset the overlayFS, reboot the node with this kernel option:
`rd.live.overlay.reset=1`.

The OverlayFS is reset by recreating the image file if it doesn't exist, and then by wiping the image
file if it does exist. The wipe is controlled by dracut-native (dmsquash-live), the creation of
the image file is handled by this dracut module (metal-squashfs-url-dracut).

[1]: https://github.com/dracutdevs/dracut/blob/master/dracut.cmdline.7.asc#booting-live-images
[2]: https://github.com/dracutdevs/dracut/blob/master/dracut.cmdline.7.asc#standard
