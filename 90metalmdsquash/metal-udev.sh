#!/bin/sh
# metal-udev.sh ; copies all new udev rules into the overlayFS

made=/etc/udev/rules.d/
live=/sysroot/etc/udev/rules.d

ls -l $live
cp -pv $made* $live/
ls -l $live

# We want our ifname rules to come after any drivers, since these denote the NIC names 
# the NCNs are intentionally providing. All other NICs are aliens, and should not be
# considered without filing a bug for investigation of origin.
ifname_rules=$live/*ifname.rules
mv $ifname_rules $live/98-ifname.rules
ls -l $live

