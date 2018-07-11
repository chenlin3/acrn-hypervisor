#!/bin/sh
#
# The script is to unpack RPM package. It has one argument of package name,
# and unpack it in current directory.
#
# rpm package format(network order)
#
# 1. Lead Part (96 bytes)
#       struct rpmlead {
#          unsigned char magic[4];
#          unsigned char major, minor;
#          short type;
#          short archnum;
#          char name[66];
#          short osnum;
#          short signature_type;
#          char reserved[16];
#    };
#
# 2. signature
# 
# 3. Header 
#
# 4. archive
#
#     The structure of signature and Header is:
#      a) header record
#              magic: 0x8eade8 (24 bit) | version (8 bits)  | resvered (32 bits) |
#	              nindex (32 b) | hsize(32b)
#      b) index_entries[]:  16B each element
#             tag 4B
#             type 4B
#             offset 4B    (offset in store)
#             count 4B     (
#      c) store for data
#
#

# $1 : the name of rpm package 
RPM_PKG=$1

# $2 : the prefix of rpm package installation the root directory
[ $# -eq 2 ] && RPM_INSTALL_DIR=$2 || RPM_INSTALL_DIR=`pwd`

if [ "${RPM_PKG}"X = "X" ] || [ ! -e "${RPM_PKG}" ]; then
	echo "Input a rpm package to install"
	exit 1
fi

echo "Installing RPM package: ${RPM_PKG}"

TMP_FILE=`mktemp`

# The size of rpmlead located at the beginning of rpm pkg
# rpmlead (96) + magic(3)+ version(1) + resv(4) = 104
set `od -j 104 -N 8 -t u1 "${RPM_PKG}"`

sig_ent_num=`expr 256 \* \( 256 \* \( 256 \* $2 + $3 \) + $4 \) + $5`
sig_data_size=`expr 256 \* \( 256 \* \( 256 \* $6 + $7 \) + $8 \) + $9`

# the total size of signature
sig_size=`expr 16 + 16 \* ${sig_ent_num} + ${sig_data_size}`

# offset to nIndex of header record of HEADER, also align to 8 bytes
offset=`expr 96 + $sig_size + 8 + 8 - $sig_size % 8`

set `od -j $offset -N 8 -t u1 $RPM_PKG`

hdr_ent_num=`expr 256 \* \( 256 \* \( 256 \* $2 + $3 \) + $4 \) + $5`
hdr_data_size=`expr 256 \* \( 256 \* \( 256 \* $6 + $7 \) + $8 \) + $9`

hdr_size=`expr 16 + 16 \* $hdr_ent_num + $hdr_data_size`
offset=`expr $offset \- 8 + $hdr_size`

dd if=$RPM_PKG of=$TMP_FILE ibs=$offset skip=1

# If the rpm package is compressed by otehr compressor, add it here :)
compressor=`file $TMP_FILE | grep -Eio 'gzip | bzip2 | xz' | tr 'A-Z' 'a-z'`

cat $TMP_FILE | $compressor -d | cpio -ivdm -D ${RPM_INSTALL_DIR}

