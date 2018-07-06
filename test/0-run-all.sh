#!/bin/bash
#
# This script is expected to run in a developement environment with Qemu and
# docker. Make sure that system has the following commands before executing 
#     wget, sha512sum, grep, xz, basename, dirname,
#     dd, fdisk, losetup, mkfs.vfat, mkfs.ext3, mount, umount,
#     docker qemu-system_x86-64
#
LOG_FILE=log.txt
[ $# -ne 0 ] && LOG_FILE=$1

# Run as root or "sudo -E "

# mounting point in docker for ACRN_HOST_DIR
export ACRN_MNT_VOL=/acrn-vol

# The folder will be mounted into docker, as ${ACRN_MNT_VOL}, "git clone"
# acrn code, build disk image(20GB) there. Make sure that it has enough
# space. The script will create it if it doesn't exist. If u don't want
# that large image, change the layout as ACRN_DISK_IMAGE
# export ACRN_HOST_DIR=/home/${USER}/vdisk
export ACRN_HOST_DIR=/work/vdisk

# The final disk image layout for qemu or dd to disk, change it as u like
export ACRN_DISK_IMAGE=clear_rootfs.img
export ACRN_DISK_SIZE=13240  # disk size (MB)
export ACRN_DISK_P1=200      # EFI ESP
export ACRN_DISK_P2=200      # Linux swap
export ACRN_DISK_P3=4096     # sos rootfs
export ACRN_DISK_P4=         # user partition uses the rest

# The release# of clearlinux in /usr/lib/os-release: like 23140, we will
# pull the image from clearlinux.org and use it to buld a docker image
# by default, we use the latest one:
#     https://cdn.download.clearlinux.org/current
 export ACRN_CLEAR_OS_VERSION=23370
# export ACRN_CLEAR_OS_VERSION=""

# download image from there. Don't change it unless u know the URL is changed
export ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# the docker image which we will create: ${DOCKER_IMAGE}:${OS_VERSION}
export ACRN_DOCKER_IMAGE=acrn-clear

# Docker created from ACRN_DOCKER_IMAGE to build source code and disk image
export ACRN_DOCKER_NAME=acrn-dev

# UEFI firmware which will be used for QEMU booting
export ACRN_UEFI_FW=OVMF-pure-efi.fd

# Save environment between scripts. Needn't touch it.
export ACRN_ENV_VARS=acrn-env.txt


[ `pwd` != ${ACRN_HOST_DIR} ] && cp *.sh ${ACRN_HOST_DIR}/

cd ${ACRN_HOST_DIR}/

# Pull KVM image of clearlinux, and build a docker image as dev environment
./1-docker-from-clear.sh 2>&1 | tee -a log.txt
[ $? -ne 0 ] && { echo "failed to build clearlinux docker image"; exit -1; }

# Create and run ClearLinux Docker
./2-setup-clearlinux-docker.sh 2>&1 | tee -a log.txt
[ $? -ne 0 ] && { echo "failed to run clearlinux docker"; exit -1; }

# prepare SOS kernel source code
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/3-prepare-sos-source.sh 2>&1 \
	| tee -a log.txt
[ $? -ne 0 ] && { echo "failed to get SOS kernel source"; exit 1; }


# prepare HV/DM source code
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/4-clone-hv-dm.sh 2>&1 | tee -a log.txt
[ $? -ne 0 ] && { echo "failed to get ACRN hypervisor source"; exit 1; }


# build source to binary
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/5-build-uefi-acrn.sh 2>&1 | tee -a log.txt
[ $? -ne 0 ] && { echo "failed to build SOS"; exit; }


# Create a disk image
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/6-mk-disk-image.sh  2>&1 | tee -a log.txt
# [ $? -ne 0 ] && { echo "failed to create disk image"; exit; }

# download OVMF efi firmware
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/7-download-ovmf.sh 2>&1 | tee -a log.txt

# change ownership
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_UEFI_FW}
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_DISK_IMAGE}
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}


docker stop  ${ACRN_DOCKER_NAME}

# For debugging, don't rm the docker
# docker rm   ${ACRN_DOCKER_NAME}

# run qemu/ovmf in local host
sed -i 's/^ACRN_/export ACRN_/g' ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}
source ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}


echo "If failed,  you can try manully staring by: qemu-system-x86_64 -bios " \
	${ACRN_HOST_DIR}/${ACRN_UEFI_FW} \
	-hda "${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE}"

qemu-system-x86_64 -bios ${ACRN_HOST_DIR}/${ACRN_UEFI_FW} -hda ${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE} -m 4G -cpu Broadwell -smp cpus=4,cores=4,threads=1
