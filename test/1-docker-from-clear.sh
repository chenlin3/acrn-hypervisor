#!/bin/bash

#
# This script is to download clearlinux kvm image and use it as a base to
# create docker image for ACRN dev environment. Because we use losetup and
# mount, "sudo -E" if running it via non-root account.
#
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
[ -z ${ACRN_HOST_DIR} ] && ACRN_HOST_DIR=/home/${USER}/vdisk
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt

# Set env vars in case we are called by 0-all script
[ -f ${ACRN_ENV_VARS} ] && \
	{ for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

[ -z ${ACRN_DOCKER_NAME} ] && ACRN_DOCKER_NAME=acrn-dev
[ -z ${ACRN_DOCKER_IMAGE} ] && ACRN_DOCKER_IMAGE=acrn-clear

# clearlinux OS version and URL. Use latest version if not specified
[ -z ${ACRN_CLEAR_OS_VERSION} ] && ACRN_CLEAR_OS_VERSION=""
[ -z ${ACRN_CLEAR_URL} ] && ACRN_CLEAR_URL=https://cdn.download.clearlinux.org

# Respect the shell environment https_proxy in Docker
[ -z ${https_proxy} ] || PROXY_CONF="-e https_proxy="${https_proxy}

PEM_SUPD='Swupd_Root.pem'
PEM_CLEAR='ClearLinuxRoot.pem'

name_conflict()
{
	RET=`docker ps -a -q --format='{{.Names}}' | grep ${ACRN_DOCKER_NAME}`
	if [ ${RET}X == ${ACRN_DOCKER_NAME}X ]; then
		echo "Container exsits or name conflict: "${ACRN_DOCKER_NAME}; 
		return 1
	fi;
	return 0;
}

# $1 - clear_os_version.
# it sets the ${CLEAR_IMAGE_FNAME} to the name of clearlinux kvm image
function get_url()
{
	### CLEAR_IMAGE_FNAME=clear-xxxxx-kvm.img.xz
	if [ $1X != "X" ]; then
		CLEAR_IMAGE_FNAME=clear-${ACRN_CLEAR_OS_VERSION}-kvm.img.xz
		IMAGE_BASE=${ACRN_CLEAR_URL}/releases/$1/clear/
	else
		# https://cdn.download.clearlinux.org/README.html the "current" folder
		# includes the latest version distribution
		IMAGE_BASE=${ACRN_CLEAR_URL}/current

		# Pattern: <a href="clear-xxxxx-kvm.img.xz">clear-xxxxx-kvm.img.xz</a>
		HREF=`curl -L ${IMAGE_BASE} | \
		    grep -Pioe "<a +href *= *\"?clear-[0-9]*-kvm.img.xz[^\-].*?</a>" | \
		    grep -Pioe \"clear-[0-9]*-kvm.img.xz\"`
		CLEAR_IMAGE_FNAME=`echo ${HREF} | sed 's/\"//g'`
		[ -z ${CLEAR_IMAGE_FNAME} ] && \
		       	{ echo "Failed to get ClearLinux image URL"; exit 1; }
	fi;

	curl -L ${IMAGE_BASE}/${PEM_SUPD} -o ${PEM_SUPD}
	curl -L ${IMAGE_BASE}/${PEM_CLEAR} -o ${PEM_CLEAR}
}

# S1: URL base of clearlinux image
# S2: image name
function download_image() 
{
	local raw_image=${2::-3}  # without .xz suffix
	[ -r $raw_image ] && { echo $raw_image " exists, just use it"; return 0; }

	[ -r $2 ] && xz -kd $2 && { echo $2 " exists, just use it"; return 0; }

	echo "Download image: " $1/$2

	wget -L -c $1/$2 && xz -kd $2 || return -1
}

# $1: ACRN_CLEAR_OS_VERSION
# $2: raw image file
function build_docker_image()
{
	set -x
	local mnt_pt=/tmp/cl_$1
	mkdir -p ${mnt_pt}
	img_loopdev=`losetup -f -P --show $2`
	mount ${img_loopdev}p3 ${mnt_pt}

	# Use the rootfs of clear-xxx-kvm.img.xz as a docker base image
	tar -C ${mnt_pt} -c . | docker import - ${USER}/${ACRN_DOCKER_IMAGE}:"t"$1

	docker create --name=${ACRN_DOCKER_NAME} --net=host  ${PROXY_CONF} \
		-v /dev:/dev/ --privileged \
		-v ${ACRN_HOST_DIR}:${ACRN_MNT_VOL} \
		-it ${USER}/${ACRN_DOCKER_IMAGE}:"t"$1 "/bin/bash"

	docker start ${ACRN_DOCKER_NAME}
	docker exec ${ACRN_DOCKER_NAME} mkdir -p /etc/ssl/certs/
	docker exec ${ACRN_DOCKER_NAME} cp ${ACRN_MNT_VOL}/${PEM_SUPD} /etc/ssl/certs/
	docker exec ${ACRN_DOCKER_NAME} cp ${ACRN_MNT_VOL}/${PEM_CLEAR} /etc/ssl/certs/
	docker exec ${ACRN_DOCKER_NAME} swupd update
	docker exec ${ACRN_DOCKER_NAME} swupd bundle-add \
		c-basic storage-utils  os-core-dev
	docker exec ${ACRN_DOCKER_NAME} pip3 install kconfiglib
	docker stop ${ACRN_DOCKER_NAME}
	docker rm ${ACRN_DOCKER_NAME}

	docker commit ${ACRN_DOCKER_NAME} ${USER}/${ACRN_DOCKER_IMAGE}:$1
	docker rmi  ${USER}/${ACRN_DOCKER_IMAGE}:"t"$1

	umount ${mnt_pt}
	losetup -D ${img_loopdev}

}

# Create the dir if doesn't exsit
mkdir -p ${ACRN_HOST_DIR}

name_conflict
[ $? -ne 0 ] && exit 1
get_url ${ACRN_CLEAR_OS_VERSION}
download_image  ${IMAGE_BASE} ${CLEAR_IMAGE_FNAME}

ACRN_CLEAR_OS_VERSION=`echo ${CLEAR_IMAGE_FNAME} | grep -ioe "[0-9]*"`

build_docker_image ${ACRN_CLEAR_OS_VERSION} ${CLEAR_IMAGE_FNAME::-3}

export ACRN_DOCKER_IMAGE=${USER}/${ACRN_DOCKER_IMAGE}:${ACRN_CLEAR_OS_VERSION}

env | grep ACRN_  > ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}

exit 0;
