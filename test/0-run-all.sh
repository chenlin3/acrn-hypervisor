#!/bin/bash
#
# This script is to create a disk image with ACRN hypervisor and service
# OS. The final disk image can be used to "dd" to USB disk or hard disk,
# to run, or run in qemu/ovmf or simics emulator.

# Make sure that system has the following commands before executing 
#     wget, curl, sha512sum, grep, sed, xz, basename, dirname,
#     guestmount/guestunmount, docker qemu-system_x86-64
#
#  package in ubuntu/centos: libguestfs,  libguestfs-tools
# 
[ $# -ne 0 ] && LOG_FILE=$1 || LOG_FILE=log.txt

# The release# of clearlinux in /usr/lib/os-release: like 23140, we will pull
# a KVM image from http://clearlinux.org and use it as base image for docker.
# By default, the latest KVM image by parsing the web page:
#               https://cdn.download.clearlinux.org/current/
# export ACRN_CLEAR_OS_VERSION=23550
export ACRN_CLEAR_OS_VERSION=""

# The folder will be mounted into docker as volume in docker's word, to the
# mounting point at ${ACRN_MNT_VOL}. It is used as work diretory (pwd) to git
# clone acrn code, build disk image(20GB). Make sure that it has enough space.
# The script will create the dir if it doens't exsit. Change layout as you like.
#
# export ACRN_HOST_DIR=/home/${USER}/vdisk
export ACRN_HOST_DIR=/work/vdisk

# The final disk image layout for qemu/ovmf or dd to disk, change it as u like
export ACRN_DISK_IMAGE=acrn_vdisk_all.img
export ACRN_DISK_SIZE=13240  # disk size (MB)
export ACRN_DISK_P1=200      # EFI ESP
export ACRN_DISK_P2=200      # Linux swap
export ACRN_DISK_P3=4096     # sos rootfs
export ACRN_DISK_P4=         # user partition uses the rest


# =========================================================================
# Most likely, you needn't modify the script after this line
# =========================================================================

# set "ACRN_TRACE_SHELL_ENABLE" to tell all scripts to "set -x". unset it if
# you don't want to trace shell commands.
# export ACRN_TRACE_SHELL=1

# Download Clearlinux OS image by the URL. Don't change it unless u know the
# URL is changed
export ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# The name of the docker image that we will create. We will alos add a tag
# by clearlinux os-version
export ACRN_DOCKER_IMAGE=acrn-clear-2

# Docker name created from ACRN_DOCKER_IMAGE as development environment to
# build ACRN source code and disk image.
export ACRN_DOCKER_NAME=acrn-dev-2

# UEFI firmware which will be used for QEMU booting. It is the filename in UEFI
# rpm package from UEFI open source project. 
export ACRN_UEFI_FW=OVMF-pure-efi.fd

# Save environment between scripts. Needn't touch it.
export ACRN_ENV_VARS=acrn-env.txt

# Mounting point in docker for ACRN_HOST_DIR. Needn't touch it
export ACRN_MNT_VOL=/acrn-vol

# Check if build environment is ok
./1-build-env-check.sh

[ `pwd` != ${ACRN_HOST_DIR} ] && cp -a *.sh ${ACRN_HOST_DIR}/

cd ${ACRN_HOST_DIR}/

# Pull KVM image of clearlinux, and build a docker image as dev environment
{ echo -n "==== Runing script 2-docker-from-clear.sh  ====@ "; date; } > ${LOG_FILE}
./2-docker-from-clear.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build clearlinux docker image"; exit -1; }

# Create and run ClearLinux Docker
{ echo -n "==== Runing script 3-setup-clearlinux-docker.sh ====@ "; date; } >> ${LOG_FILE}
./3-setup-clearlinux-docker.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to run clearlinux docker"; exit -1; }

# prepare SOS kernel source code
{ echo -n "==== Runing script 4-prepare-sos-source.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/4-prepare-sos-source.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get SOS kernel source"; exit 1; }

# prepare HV/DM source code
{ echo -n "==== Runing script 5-clone-hv-dm.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/5-clone-hv-dm.sh 2>&1 | \
       	tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get ACRN hypervisor source"; exit 1; }

# build source to binary
{ echo -n "==== Runing script 6-build-uefi-acrn.sh  ====@ "; date; }  >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/6-build-uefi-acrn.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build SOS"; exit; }

# Create a disk image
{ echo -n "==== Runing script 7-mk-disk-image.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/7-mk-disk-image.sh  2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to create disk image"; exit; }

# download OVMF efi firmware
{ echo -n "==== Runing script 8-download-ovmf.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/8-download-ovmf.sh 2>&1 \
	| tee -a ${LOG_FILE}

# change ownership
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_UEFI_FW}
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_DISK_IMAGE}
docker exec ${ACRN_DOCKER_NAME} chmod 777 ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}

docker stop  ${ACRN_DOCKER_NAME}

# Comment this if you want to keep the docker as a build environment
# docker rm  ${ACRN_DOCKER_NAME}

# run qemu/ovmf in local host
sed -i 's/^ACRN_/export ACRN_/g' ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}
source ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}


echo "If failed, trying manually starting qemu by: qemu-system-x86_64 -bios " \
	${ACRN_HOST_DIR}/${ACRN_UEFI_FW} \
	-hda "${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE}"

qemu-system-x86_64 -bios ${ACRN_HOST_DIR}/${ACRN_UEFI_FW} -hda ${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE} -m 4G -cpu Broadwell -smp cpus=4,cores=4,threads=1 -serial stdio

