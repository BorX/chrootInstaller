#!/bin/bash

# #############################################################################
# Script vars

EXIT_CODE_OK=0
EXIT_CODE_USER_HAVE_TO_BE_ROOT=1
EXIT_CODE_NO_DEBOOTSTRAP=2
EXIT_CODE_CONF_FILE_NOT_READABLE=3
EXIT_CODE_INVALID_PARAMETER=4
EXIT_CODE_SUITE_DOESNT_EXIST=5
EXIT_CODE_PARTITION_DOESNT_EXIST=6
EXIT_CODE_PARTITION_CANNOT_MKFS=7
EXIT_CODE_PARTITION_CANNOT_MOUNT=8
EXIT_CODE_PATH_DOESNT_EXIST=9
EXIT_CODE_BOOTSTRAPING=10

CONF_FILE="$(dirname $0)/$(basename $0 sh)conf"


# #############################################################################
# Functions

showMessage() {
	cat <<< "$*"
}

showTitle1() {
	showMessage "
===============================================================================
==  $*"
}

showTitle2() {
	showMessage "
-------------------------------------------------------------------------------
--  $*"
}

showError() {
	showMessage "$*" >&2
}

showErrorAndExit() {
	local ret=$1
	shift
	showError "$*"
	umount $TARGET_PATH/dev $TARGET_PATH 2>/dev/null
	exit $ret
}


# #############################################################################
# Prerequisites checking

showTitle1 'Checking prerequisites'

# Check if user is root
[ $(id -u) -eq 0 ] || showErrorAndExit $EXIT_CODE_USER_HAVE_TO_BE_ROOT 'Script can only be invoked by root'
showMessage 'User is root'

# Is debootstrap here
DEBOOTSTRAP_CMD="$(which debootstrap)" || showErrorAndExit $EXIT_CODE_NO_DEBOOTSTRAP 'debootstrap is not installed'
showMessage "deboostrap : using $DEBOOTSTRAP_CMD"

showTitle2 'Configuration'
# Loading configuration file
[ -r "$CONF_FILE" ] || showErrorAndExit $EXIT_CODE_CONF_FILE_NOT_READABLE "$CONF_FILE is not readable"
. "$CONF_FILE"
# Showing parameters
[ -n "$TARGET_PARTITION" ] && showMessage "TARGET_PARTITION=$TARGET_PARTITION" || showMessage "TARGET_PATH=$TARGET_PATH"
showMessage "SUITE=$SUITE
TARGET_NAME=$TARGET_NAME
MIRROR=$MIRROR"

# Checking parameters
[[ (-z "$TARGET_PARTITION" && -z "$TARGET_PATH") || -z "$SUITE" || -z "$TARGET_NAME" || -z "$MIRROR" ]] && showErrorAndExit $EXIT_CODE_INVALID_PARAMETER 'Invalid parameter(s)'
[ -r "/usr/share/debootstrap/scripts/$SUITE" ] || showErrorAndExit $EXIT_CODE_SUITE_DOESNT_EXIST "$SUITE is not a known suite"


# #############################################################################
# Target directory
# Using a partition
showTitle1 'Preparing target'
[ -n "$TARGET_PARTITION" ] && {
	[ -e "$TARGET_PARTITION" ] || showErrorAndExit $EXIT_CODE_PARTITION_DOESNT_EXIST "$TARGET_PARTITION does not exist"

	# Partition formatting
	showMessage "Making filesystem ext3 on $TARGET_PARTITION"
	mkfs.ext3 -L "$SUITE" "$TARGET_PARTITION" || showErrorAndExit $EXIT_CODE_PARTITION_CANNOT_MKFS "Something was wrong during making filesystem ext3 on $TARGET_PARTITION"

	# Partition mounting
	TARGET_PATH=$(mktemp -d)
	showMessage "Mounting $TARGET_PARTITION on $TARGET_PATH"
	mount "$TARGET_PARTITION" "$TARGET_PATH" || showErrorAndExit $EXIT_CODE_PARTITION_CANNOT_MOUNT "Something was wrong during mounting $TARGET_PARTITION on $TARGET_PATH"
} || {
	# Using a directory
	[ -n "$TARGET_PATH" ] && {
		mkdir -p "$TARGET_PATH" || showErrorAndExit $EXIT_CODE_PATH_DOESNT_EXIST "$TARGET_PATH does not exist and cannot be made"
	}
	showMessage "Using directory $TARGET_PATH"
}


# #############################################################################
# System base installation

showTitle1 "Bootstraping basic system on $SUITE into $TARGET_PATH from $MIRROR"
$DEBOOTSTRAP_CMD $SUITE "$TARGET_PATH" $MIRROR || showErrorAndExit $EXIT_CODE_BOOTSTRAPING "Something was wrong during bootstraping basic system on $SUITE into $TARGET_PATH from $MIRROR"


# #############################################################################
# Connfiguration du nouveau systeme

showTitle1 'Configuration of the new system'

# /etc/hostname
showMessage "Modification of hostname to $TARGET_NAME"
echo "$TARGET_NAME" > "$TARGET_PATH/etc/hostname"

# /opt/autoPostInstall
cp -av autoPostInstall "$TARGET_PATH/opt/"
chmod 700 "$TARGET_PATH/opt/autoPostInstall/autoPostInstall.sh"

# /etc/network/interfaces
cp -av /etc/network/interfaces "$TARGET_PATH/etc/network/"

# /etc/hosts
showMessage 'Modification of /etc/hosts'
sed "s/\(127.0.0.1.*$\)/\1 $TARGET_NAME/" /etc/hosts > "$TARGET_PATH/etc/hosts"

# /etc/fstab
showMessage 'Modification of /etc/fstab'
awk '$1 !~ /^#/ && $2=="/" {$1="'$TARGET_PARTITION'"} {print}' /etc/fstab > "$TARGET_PATH/etc/fstab"


# #############################################################################
# Lancement du script de post-installation en chroot

showTitle1 'Post-installation in chroot'

mount -o bind /dev "$TARGET_PATH/dev"
chroot "$TARGET_PATH" "/opt/autoPostInstall/autoPostInstall.sh"


# #############################################################################
# Demontage de la partition

umount "$TARGET_PATH/dev"
[ -n "$TARGET_PARTITION" ] && umount "$TARGET_PATH" && rmdir "$TARGET_PATH"

cat <<EOF
Other files to change/verify :
- /etc/debian_version
- /etc/fstab (and mount points are OK)
- SSH configuration (keys, ...)
- /etc/sudoers
- /etc/vim/vimrc
EOF

exit $EXIT_CODE_OK

