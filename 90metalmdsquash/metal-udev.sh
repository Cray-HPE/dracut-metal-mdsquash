#!/bin/bash
# metal-udev.sh ; copies all new udev rules into the overlayFS

made=/etc/udev/rules.d/
live=/sysroot/etc/udev/rules.d

ls -l $live
cp -pv $made* $live/
ls -l $live

# We want our ifname rules to come after any drivers, since these denote the NIC names 
# the NCNs are intentionally providing. All other NICs are aliens, and should not be
# considered without filing a bug for investigation of origin.
# ifname.rules must run after these rules:
# 82-net-setup-link.rules
# ifname.rules must run before these rules:
# 85-persistent-net-cloud-init.rules
# 90-net.rules - this UPs our named nics
#
ls -l $live
ifname_rules=$live/*ifname.rules
mv $ifname_rules $live/84-ifname.rules
ls -l $live
