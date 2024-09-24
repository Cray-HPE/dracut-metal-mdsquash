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
Name: %(echo $NAME)
Packager: <doomslayer@hpe.com>
Release: 1
Vendor: Hewlett Packard Enterprise Development LP
Version: %(echo $VERSION)
Source: %{name}-%{version}.tar.bz2
BuildArch: noarch
Group: System/Management
License: MIT License
Summary: Dracut module for loading squashFS and persistent overlays
Provides: metal-mdsquash
Conflicts: dracut-metal-dmk8s <= 2.0.6
Conflicts: dracut-metal-luksetcd <= 2.1.2

Requires: coreutils
Requires: curl
Requires: diffutils
Requires: dosfstools
Requires: dracut
Requires: e2fsprogs
Requires: efibootmgr
Requires: iputils
Requires: lvm2
Requires: mdadm
Requires: parted
Requires: util-linux
Requires: util-linux-systemd
Requires: xfsprogs

%define dracut_modules /usr/lib/dracut/modules.d
%define module_name 90metalmdsquash
Provides: %{module_name}
%define url_dracut_doc /usr/share/doc/metal/%{module_name}/

%description

%prep

%setup -q

%build
%define hash %(git rev-parse --verify HEAD)
if [ -n %{hash} ]; then
    echo %{hash}
sed -i 's,@@metal-hash@@,%{hash},g' %{module_name}/metal-lib.sh
fi

%install
%{__mkdir_p} %{buildroot}%{url_dracut_doc}
%{__mkdir_p} %{buildroot}%{dracut_modules}/%{module_name}
cp -pvrR ./%{module_name}/* %{buildroot}%{dracut_modules}/%{module_name} | awk '{print $3}' | sed "s/'//g" | sed "s|$RPM_BUILD_ROOT||g" | tee -a INSTALLED_FILES
%{__install} -m 0644 README.adoc %{buildroot}%{url_dracut_doc}

%files -f INSTALLED_FILES
%defattr(0755, root, root)
%license LICENSE
%dir %{dracut_modules}/%{module_name}
%dir %{url_dracut_doc}
%attr(644, root, root) %{url_dracut_doc}/README.adoc

%pre

%post

%preun

%posttrans
mkinitrd -B

%changelog
