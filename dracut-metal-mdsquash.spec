#
# MIT License
#
# (C) Copyright 2022 Hewlett Packard Enterprise Development LP
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
%define namespace dracut
# disable compressing files
%define __os_install_post %{nil}
%define intranamespace_name metal-mdsquash
%define x_y_z %(echo $VERSION)
%define release_extra %(if [ -e "%{_sourcedir}/_release_extra" ] ; then cat "%{_sourcedir}/_release_extra"; else echo ""; fi)
%define source_name %{name}

################################################################################
# Primary package definition #
################################################################################

Name: %{namespace}-%{intranamespace_name}
Packager: <doomslayer@hpe.com>
Release: 1
Vendor: Cray HPE
Version: %{x_y_z}
Source: %{source_name}-%{version}.tar.bz2
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}
Group: System/Management
License: MIT License
Summary: Install the Metal dracut module for loading squashFS and persistent overlays
Provides: metal-mdsquash
Provides: 90metalmdsquash

Requires: coreutils
Requires: curl
Requires: dracut
Requires: dosfstools
Requires: e2fsprogs
Requires: efibootmgr
Requires: iputils
Requires: lvm2
Requires: mdadm
Requires: parted
Requires: util-linux-systemd
Requires: xfsprogs

%define dracut_modules /usr/lib/dracut/modules.d
%define url_dracut_doc /usr/share/doc/metal-dracut/mdsquash/
%define module_name 90metalmdsquash

%description

%prep

%setup

%build

%install
%{__mkdir_p} %{buildroot}%{url_dracut_doc}
%{__mkdir_p} %{buildroot}%{dracut_modules}/%{module_name}
cp -pvrR ./%{module_name}/* %{buildroot}%{dracut_modules}/%{module_name} | awk '{print $3}' | sed "s/'//g" | sed "s|$RPM_BUILD_ROOT||g" | tee -a INSTALLED_FILES
%{__install} -m 0644 README.md %{buildroot}%{url_dracut_doc}

%files -f INSTALLED_FILES
%defattr(0755, root, root)
%license LICENSE
%dir %{dracut_modules}/%{module_name}
%dir %{url_dracut_doc}
%attr(644, root, root) %{url_dracut_doc}/README.md

%pre

%post

%preun

%changelog
