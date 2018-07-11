#!/bin/bash
#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing
#     grep, basename, dirname,
# 
# In this foleder, We "git clone" all ACRN repos, and then build disk image.
# Make sure that it has 30GB  space or you change reduce the image disze.
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
cd ${ACRN_MNT_VOL} || { echo "Failed to cd "${ACRN_MNT_VOL}; exit -1; }

[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
    { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }


[ -z ${ACRN_HV_DIR} ] && ACRN_HV_DIR=${ACRN_MNT_VOL}"/acrn-hypervisor"
[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

build_sos_kernel() {
        cd ${ACRN_SOS_DIR} || return 1

        # add_to_makefile
        grep "export INSTALL_PATH=\$(PWD)/out" Makefile 1>/dev/null

	# If we add it before, don't repeat it
        if [ $? -ne 0 ]; then
	sed -i '/^EXTRAVERSION =.*/  s/$/-acrn/' Makefile
        sed -i '1i PWD=$(shell pwd)\nEXTRAVERSION=-acrn\n' Makefile
        sed -i '2a export INSTALL_PATH=$(PWD)/out' Makefile
        sed -i '3a export INSTALL_MOD_PATH=$(PWD)/out' Makefile
#        sed -i '4a export CCACHE_DISABLE=1' Makefile

        # remove firmware compiling in kconfig
#        sed -i '/CONFIG_EXTRA_FIRMWARE/'d  .config
#        sed -i '1i   CONFIG_EXTRA_FIRMWARE=""'  .config
#        sed -i '/CONFIG_EXTRA_FIRMWARE_DIR/'d .config

	# Build USB keyboard and mouse so that users can work in the console
        sed -i 's/^CONFIG_USB_HID[ =].*$/CONFIG_USB_HID=m\nCONFIG_USB_KBD=m\nCONFIG_USB_MOUSE=m\n/' .config

        # built-in USB XHCI host controller drivers
        sed -i 's/.*CONFIG_USB_XHCI_HCD[ =].*$/CONFIG_USB_XHCI_HCD=y/' .config
        sed -i 's/.*CONFIG_USB_XHCI_PCI[ =].*$/CONFIG_USB_XHCI_PCI=y/' .config
        sed -i 's/.*CONFIG_USB_XHCI_PLATFORM[ =].*$/CONFIG_USB_XHCI_PLATFORM=y/' .config
        fi;

        # accept default options (no firmware build)
        (echo -e "n\nn\nn\nn\nn\n") | make 
        make modules
	make bzImage
        make modules_install

	CLEAR_ID=`grep -n 'ID[ ]*=*clear-*linux' /usr/lib/os-release`

	# Clearlinux doesn't allow us to install modules into other dirs except
	# /usr/lib/modules. Refer to /usr/bin/installkernel in Clearlinux
        if [ -z ${CLEAR_ID} ]; then
                make install
        else
                version=`basename  ${ACRN_SOS_DIR}`
                cp arch/x86/boot/bzImage out/vmlinuz-${version:6}"-acrn"

        fi
}


# ccache causes the build failure on clearlinux-kvm-23370. Disable it
export CCACHE_DISABLE=1

# build service OS
cd ${ACRN_MNT_VOL} && build_sos_kernel || { echo "Failed to build service OS"; exit 1; }

# build acrn hypervisor, device module and tools
cd ${ACRN_MNT_VOL} && cd ${ACRN_HV_DIR} && make PLATFORM=uefi || \
	{ echo "Failed to build hypervisor"; exit 1; }

env | grep ACRN > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}


