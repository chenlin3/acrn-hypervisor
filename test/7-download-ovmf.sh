#!/bin/bash
# 


# This volume on host system, and has been mounted into acrn-dev docker
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
cd ${ACRN_MNT_VOL} || { echo "Failed to cd "${ACRN_MNT_VOL}; exit -1; }

[ -f ${ACRN_ENV_VARS} ] && \
	                { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_DISK_IMAGE} ] && ACRN_DISK_IMAGE=./clear_rootfs.img

[ -z ${ACRN_TRACE_SHELL_ENABLE} ] || set -x

URL_EDK2="https://www.kraxel.org/repos/jenkins/edk2"
echo "Trying to access " ${URL_EDK2} " to get OVMF.fd"

# Get the string:  <a href="edk2.git-ovmf-x64-0-20180508.84.g7cd8a57599.noarch.rpm">
STR_HREF=`curl -L ${URL_EDK2} | grep -Pioe "<a *href *= *\"edk2.git-ovmf-x64.*?</a>"  | \
	grep -Pioe "edk2.git-ovmf-x64.*?\">"`
[ -z ${STR_HREF} ] && { echo "Failed to get OVMF URL"; exit 1; }

OVMF_RPM=${STR_HREF::-2}


if [ -f ${OVMF_RPM} ]; then
      echo "The rpm package exists. Use the olde one."
else
	wget -q -L -c ${URL_EDK2}/${OVMF_RPM}
fi;
[ -f ${OVMF_RPM} ] || echo "Failed to download OVMF rpm: " ${URL_EDK2}/${OVMF_RPM}

`which rpm2cpio > /dev/null`
if [ $? -eq 0 ]; then
	rpm2cpio ${OVMF_RPM} | cpio -idvm
else
	./7-z-unpack-rpm.sh ${OVMF_RPM}
fi;


OVMF_FD=`find ./usr | grep OVMF-pure-efi.fd`

[ -f ${OVMF_FD} ] || { echo "Failed to get OVMF file from rpm package"; exit -1; }

cp ${OVMF_FD} .

export ACRN_UEFI_FW=`basename ${OVMF_FD}`

env | grep ACRN > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}

