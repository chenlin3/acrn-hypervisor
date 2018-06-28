#!/bin/bash

#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing 
#     wget, sha512sum, grep, xz, basename, dirname,
#     dd, fdisk, losetup, mkfs.vfat, mkfs.ext3, mount, umount,
#
# https_proxy=http://example.com:999
# Respect the shell environment https_proxy in Docker
[ -z ${https_proxy} ] || PROXY_CONF="-e https_proxy="${https_proxy}


# This is the volume on host system, and will be mounted into docker
# "-v ${ACRN_HOST_DIR}:${ACRN_MNT_VOL}. We "git clone" all ACRN repos, 
# and then build disk image there in docker. Make sure that it has 30GB
# space since disk image will be created there.
[ -z ${ACRN_HOST_DIR} ] && ACRN_HOST_DIR=/home/${USER}/vdisk
[ -z ${ACRN_MNT_VOL} ] && ACRN_MNT_VOL=/acrn-vol
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt

# Set env vars in case we are called by 0-all script
[ -f ${ACRN_ENV_VARS} ] && \
        { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

# The image is used to create a docker to build ACRN source code.
[ -z ${ACRN_DOCKER_IMAGE} ] && ACRN_DOCKER_IMAGE=acrn-clear
[ -z ${ACRN_DOCKER_NAME} ] && ACRN_DOCKER_NAME=acrn-dev

set -x

# Create the dir if doesn't exsit
mkdir -p ${ACRN_HOST_DIR}

is_container_name_conflict() {
	RET=`docker ps -a -q --format='{{.Names}}' | grep ${ACRN_DOCKER_NAME}`
	if [ ${RET}X == ${ACRN_DOCKER_NAME}X ]; then
		echo "Container exsits or name conflict: "${ACRN_DOCKER_NAME}; 
		return 1
	fi;
	return 0;
}

is_container_name_conflict
[ $? -ne 0 ] && exit 1

# copy scripts into the folder which will be mounted into container
[ `pwd` != ${ACRN_HOST_DIR} ] && cp *.sh ${ACRN_HOST_DIR}/


# if local image exist; don't download it again unless it has "latest" tag
docker inspect ${ACRN_DOCKER_IMAGE} > /dev/null
if [ $? -ne 0 ] || [ ${ACRN_DOCKER_IMAGE##*:}X == "latestX" ]; then
	docker pull ${ACRN_DOCKER_IMAGE}
else
	echo "Image is in local repo."
fi;

# Need to access /dev/loopX device, privileged is required :(
docker create -it -v /dev:/dev/ --privileged --name=${ACRN_DOCKER_NAME} \
	-v ${ACRN_HOST_DIR}:${ACRN_MNT_VOL} --net=host \
	-e "ACRN_MNT_VOL=${ACRN_MNT_VOL}" ${PROXY_CONF} \
	-e "ACRN_ENV_VARS=${ACRN_ENV_VARS}" \
	--entrypoint "/bin/bash" ${ACRN_DOCKER_IMAGE} 

docker start ${ACRN_DOCKER_NAME} && exit 0;

env | grep ACRN_  > ${ACRN_HOST_DIR}/${ACRN_ENV_VARS}

exit 1;

# docker attach ${ACRN_DOCKER_NAME}
