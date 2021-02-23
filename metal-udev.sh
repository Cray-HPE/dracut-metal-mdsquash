#!/bin/sh

made=/etc/udev/rules.d/
live=/run/overlayfs/etc/udev/rules.d/

ls -l $live
cp -pv $made* $live
ls -l $live
