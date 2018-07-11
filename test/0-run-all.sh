#!/bin/bash
#
# This script is expected to run in a developement environment with Qemu and
# docker. Make sure that system has the following commands before executing 
#     wget, sha512sum, grep, xz, basename, dirname,
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


# The folder will be mounted into docker as volume in docker's work,  to the
# mounting point at ${ACRN_MNT_VOL}. We use it as work diretory (pwd) to git
# clone acrn code, build disk image(20GB). Make sure that it has enough space.
# If the dir doesn't exist, the script will create it if not exist. Change the
# layout as you like.
# export ACRN_HOST_DIR=/home/${USER}/vdisk
export ACRN_HOST_DIR=/work/vdisk333

# The final disk image layout for qemu/ovmf or dd to disk, change it as u like
export ACRN_DISK_IMAGE=clear_rootfs.img
export ACRN_DISK_SIZE=13240  # disk size (MB)
export ACRN_DISK_P1=200      # EFI ESP
export ACRN_DISK_P2=200      # Linux swap
export ACRN_DISK_P3=4096     # sos rootfs
export ACRN_DISK_P4=         # user partition uses the rest


# =========================================================================
# Most likely, you needn't modify the other after this line
# =========================================================================


# Download Clearlinux OS image by the URL. Don't change it unless u know the
# URL is changed
export ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# set "ACRN_TRACE_SHELL_ENABLE" to tell all scripts to "set -x". unset it if
# you don't want to trace shell commands.
# export ACRN_TRACE_SHELL=1

# The name of the docker image that we will create. We will alos add a tag
# by clearlinux os-version
export ACRN_DOCKER_IMAGE=acrn-clear

# Docker name created from ACRN_DOCKER_IMAGE as development environment to
# build ACRN source code and disk image.
export ACRN_DOCKER_NAME=acrn-dev

# UEFI firmware which will be used for QEMU booting. It is the filename in UEFI
# rpm package from UEFI open source project. 
export ACRN_UEFI_FW=OVMF-pure-efi.fd

# Save environment between scripts. Needn't touch it.
export ACRN_ENV_VARS=acrn-env.txt

# Mounting point in docker for ACRN_HOST_DIR. Needn't touch it
export ACRN_MNT_VOL=/acrn-vol

# Check if build environment is ok
./0-z-build-env-check.sh

[ `pwd` != ${ACRN_HOST_DIR} ] && cp -a *.sh ${ACRN_HOST_DIR}/

cd ${ACRN_HOST_DIR}/


# Only the fist script (1-docker-from-clear.sh) needs to run with "sudo -E"
# because it uses "losetup" and "mount" commands in host system to get the
# base image (rootfs) from clearlinux KVM image.
#
# Pull KVM image of clearlinux, and build a docker image as dev environment
{ echo -n "==== Runing script 1-docker-from-clear.sh  ====@ "; date; } > ${LOG_FILE}
./1-docker-from-clear.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build clearlinux docker image"; exit -1; }


# Create and run ClearLinux Docker
{ echo -n "==== Runing script 2-setup-clearlinux-docker.sh ====@ "; date; } >> ${LOG_FILE}
./2-setup-clearlinux-docker.sh 2>&1 | tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to run clearlinux docker"; exit -1; }



# prepare SOS kernel source code
{ echo -n "==== Runing script 3-prepare-sos-source.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/3-prepare-sos-source.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get SOS kernel source"; exit 1; }



# prepare HV/DM source code
{ echo -n "==== Runing script 4-clone-hv-dm.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME}  ${ACRN_MNT_VOL}/4-clone-hv-dm.sh 2>&1 | \
       	tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to get ACRN hypervisor source"; exit 1; }

# build source to binary
{ echo -n "==== Runing script 5-build-uefi-acrn.sh  ====@ "; date; }  >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/5-build-uefi-acrn.sh 2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to build SOS"; exit; }

# Create a disk image
{ echo -n "==== Runing script 6-mk-disk-image.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/6-mk-disk-image.sh  2>&1 \
	| tee -a ${LOG_FILE}
[ $? -ne 0 ] && { echo "failed to create disk image"; exit; }

# download OVMF efi firmware
{ echo -n "==== Runing script 7-download-ovmf.sh  ====@ "; date; } >> ${LOG_FILE}
docker exec ${ACRN_DOCKER_NAME} ${ACRN_MNT_VOL}/7-download-ovmf.sh 2>&1 \
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


echo "If failed,  you can try manully staring by: qemu-system-x86_64 -bios " \
	${ACRN_HOST_DIR}/${ACRN_UEFI_FW} \
	-hda "${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE}"

qemu-system-x86_64 -bios ${ACRN_HOST_DIR}/${ACRN_UEFI_FW} -hda ${ACRN_HOST_DIR}/${ACRN_DISK_IMAGE} -m 4G -cpu Broadwell -smp cpus=4,cores=4,threads=1
