# Copyright 2020 Hewlett Packard Enterprise Development LP
%define namespace dracut
# disable compressing files
%define __os_install_post %{nil}
%define intranamespace_name metal-mdsquash
%define x_y_z %(cat .version)
%define release_extra %(if [ -e "%{_sourcedir}/_release_extra" ] ; then cat "%{_sourcedir}/_release_extra"; else echo ""; fi)
%define source_name %{name}

################################################################################
# Primary package definition #
################################################################################

Name: %{namespace}-%{intranamespace_name}
Packager: <doomslayer@hpe.com>
Release: %(echo ${BUILD_METADATA})
Vendor: Cray HPE
Version: %{x_y_z}
Source: %{source_name}.tar.bz2
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}
Group: System/Management
License: MIT License
Summary: Install the Metal dracut module for loading squashFS and persistent overlays
Provides: metal-mdsquash
Provides: 90metalmdsquash

Requires: rpm
Requires: coreutils
Requires: dracut
Requires: iputils

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
