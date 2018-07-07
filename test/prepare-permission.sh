#!/bin/bash

# libguestfs  libguestfs-tools

# check if a group in group list: $1 group; $2 group list;
function user_in_group() {
	for g in $2; do
		[ $g == $1 ] && return 1;
	done
	return 0;
}

function has_docker_group() {
	local tmp=`grep -Pioe "^docker:" /etc/group` >> /dev/null
	[ ${tmp}X == "docker:"X ] && return 1;
	return 0
}

group_list=`groups`
kvm_group=`stat -c %G /dev/kvm`
CURR_USER=`whoami`

# Ensure that host system has "docker" user group 
has_docker_group
if [ $? -eq 0 ]; then
	echo -n "Need to create a docker group by: \"groupadd docker\", "
	echo -n "and then add" ${CURR_USER} "into the group by:"
	echo -e "  \"usermod -a ${CURR_USER} -G docker\""
	exit 1
fi;

# ensure current user is in docker group
user_in_group "docker" ${group_list}
if [ $? -eq 0 ]; then
	echo -n "Need to add" \"${CURR_USER}\" "into group" \"docker\" "by:"
	echo -e "  \"usermod -a ${CURR_USER} -G docker\""
fi;

# ensure current user is in kvm group
user_in_group ${kvm_group} ${group_list}
if [ $? == 0 ]; then
	echo -n "Need to add" \"${CURR_USER}\" "into group" \"${kvm_group}\" "by:"
	echo -e "  \"usermod -a ${CURR_USER} -G ${kvm_group}\""
fi;



