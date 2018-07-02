#!/bin/bash
#
# This script is expected to run in ClearLinux host or docker developement
# environment. Make sure system has the following commands before executing
#     wget, grep, tar, xz, basename, dirname,
#
# It does:
#   1. git clone https://github.com/clearlinux-pkgs/linux-pk414
#   2. wget -c https://www.kernel.org/pub/linux/kernel/v4.x/linux-4.14.xxx.tar.xz
#   3. tar xJf linux-4.14.xxx.tar.xz
#   4. cd linux-4.14.xxx
#   5. for i in `ls ../linux-pk414/*.patch`; do patch -p1 <$i; done;
#   6. cp ../linux-pk414/config-pk414-sos  .config
#
set -x
[ -z ${ACRN_ENV_VARS} ] && ACRN_ENV_VARS=acrn-env.txt
[ -f ${ACRN_ENV_VARS} ] && \
    { for line in `cat ${ACRN_ENV_VARS}`; do export $line; done; }

cd ${ACRN_MNT_VOL};

# All works will be done in this folder. We "git clone" all ACRN repositories,
# compile, and then build disk image there. Make sure that it has 30GB space



# The dirname of Linux kernel source for SOS.
# "auto" tells the script to use latest kernel based on clearlinux linux-pk414.
# The rpmbuild spec file in clearlinux linux-pkt414 repo indicates the kenrel 
# version. Bease that, we download a tarball from www.kernel.org, uncompress
# it. If u have a stable kernel git and checkout the right version, set this. 
# For exmaple, linux-4.14.39
ACRN_SOS_DIR="auto"

# In linux-pk414 git, there is linux-pk414.spec file. Get kernel base
# from the "Source0: https://" in that file.
get_base_kernel_version() {
	cd linux-pk414
	RPM_SPEC=`ls *.spec`
        if ! [ -r ${RPM_SPEC} ]; then
           echo "Failed to find linux rpmbuild spec file in "`pwd`
           exit -1
        fi;
        SOURCE=`(grep -i "SOURCE0" ${RPM_SPEC})`
        INDEX=`(expr index "${SOURCE}" "https://")`
        URL_STABLE_KERNEL=${SOURCE:${INDEX}}
        cd ../
	KERNEL_XZ=`basename ${URL_STABLE_KERNEL}`
	ACRN_SOS_DIR=`echo ${KERNEL_XZ/.tar.xz/}`
}

# wget is faster than git clone stable kernel. If you already has stable
# tree, git checkout it to replace the func
wget_kernel() {
	[ -d ${ACRN_SOS_DIR} ] && { echo "SOS source exsits, use the old"; return 0; }
	
	if [ -r ${KERNEL_XZ} ]; then
		echo ${KERNEL_XZ}" exsits, will use it instead of download it again"
	else
		echo "Downloading kernel: "${URL_STABLE_KERNEL}
		wget -c ${URL_STABLE_KERNEL}
	fi;
	
	[ $? -ne 0 ] && return 1
	tar xJf ${KERNEL_XZ} 
	[ $? -ne 0 ] && return 1
	return 0
}


# patch stable kernel with ACRN sos patch set
apply_patches() {
        cd ${ACRN_SOS_DIR} || return 1
        for i in `ls ../linux-pk414/*.patch`; do patch -p1 <$i; done;
        if [ $? -eq 0 ]; then
                echo "Completed patching !"
        else
                echo "Failed to apply patches or already patched ???"
        fi;
        cp ../linux-pk414/config-pk414-sos  .config
}

# clone pkt414 kenrel, which hosts the SOS kernel patches. If it exists,
# we don't update it (git pull), instead assume that you want to use the
# old one.  You can update it before runnoing the script
if [ -d ./linux-pk414 ]; then
        echo "linux-pk414 exsits.  Use the old git"
else
        echo "git clone linx-pk414"
        git clone https://github.com/clearlinux-pkgs/linux-pk414
fi;


[ ${ACRN_SOS_DIR}X == "auto"X ] && get_base_kernel_version

# use the existing SOS kernel base or donwload it
[ -d ${ACRN_SOS_DIR} ] ||  wget_kernel 
[ $? -ne 0 ] && exit 1;

# apply the patches in pk414 repo to SOS kernel
[ -d ${ACRN_SOS_DIR} ] && apply_patches

# export it in Docker and indicate that SOS source is Ok
export ACRN_SOS_DIR=${ACRN_SOS_DIR}

echo "Stable kernel source in: "${ACRN_SOS_DIR}

env | grep ACRN_ > ${ACRN_MNT_VOL}/${ACRN_ENV_VARS}
