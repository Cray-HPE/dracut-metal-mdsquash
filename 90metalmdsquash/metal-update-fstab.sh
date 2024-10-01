#!/bin/bash
#
# MIT License
#
# (C) Copyright 2022-2024 Hewlett Packard Enterprise Development LP
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
[ "${METAL_DEBUG:-0}" = 0 ] || set -x
command -v metal_die > /dev/null 2>&1 || . /lib/metal-lib.sh

fstab_metal_new=$METAL_FSTAB
fstab_metal_old=/sysroot$METAL_FSTAB
fstab_metal_temp=${METAL_FSTAB}.merged

# If a new FSTab exists, this copies it regardless if there is no diff.
if [ -f "$fstab_metal_new" ]; then

  # If no prior fstab exists, copy the new one into place.
  if [ ! -f "$fstab_metal_old" ]; then
    cp -v "$fstab_metal_new" "$fstab_metal_old"

  # If a prior fstab exists, merge it and verify all the labels exist before copying it into place.
  elif diff -q "$fstab_metal_old" "$fstab_metal_new"; then

    # Make new fstab file, remove commented out lines.
    cat "$fstab_metal_old" "$fstab_metal_new" | sort -u | grep -v '^#' > "$fstab_metal_temp"

    # If no errors, copy the merged fstab into place. Otherwise fail with a fatal error for inspection.
    cp -v "$fstab_metal_temp" "$fstab_metal_old"
  fi
fi
