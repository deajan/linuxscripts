#!/usr/bin/env bash

PROGRAM="ssh_jail.sh" # Basic ssh shell jail creation script
AUTHOR="(L) 2014 by Orsiris \"Ozy\" de Jong"
CONTACT="http://www.netpower.fr - ozy@netpower.fr"
PROGRAM_BUILD=2108201403

## Creates a SSH chroot jail where a given user can login and execute a minimal set of programs
## Binaries specified by BINARIES_TO_COPY will be available
## You may also specifiy /usr/bin and /lib in EXT_DIRS to gain multiple binaries

## If you need support for editing programs, consider adding /usr/share/terminfo (CentOS) or /lib/terminfo directories (Debian) to EXT_DIRS


# List of binary files to copy to chrooted environment. All dependencies will also be copied.
BINARIES_TO_COPY="/usr/bin/chmod;/usr/bin/chown;/usr/bin/ls;/usr/bin/cat;/usr/bin/ln;/usr/bin/cp;/usr/sbin/ldconfig" # Works on CentOS 7
#BINARIES_TO_COPY="/bin/chmod;/bin/chown;/bin/ls;/bin/cat;/bin/ln;/bin/cp;/bin/mv;/bin/rm;/usr/bin/curl" # Works on Debian 6

# Directories to copy to chrooted environment
# /etc/php.d is needed to support php modules
# /usr/share/terminfo or /lib/terminfo is needed to support interactive programs like nano or php
# /usr/share/snmp is needed for php-snmp module
# /usr/share/zoneinfo is needed for php-composer
EXT_DIRS="/usr/bin;/usr/lib64;/usr/share/php;/usr/share/terminfo;/usr/include;/etc/php.d;/usr/share/snmp;/usr/share/zoneinfo;/etc/ld.so.conf.d" # Works on CentOS 7 (replace lib by lib64 if needed)
#EXT_DIRS="/bin;/lib;/lib/terminfo" # Works on Debian 6 (replace lib by lib64 if needed)
#EXT_DIRS="/lib/terminfo"

# Empty directories to create in chrooted environment types (lib and lib64 directories are already included)
DIRS_TO_CREATE="/dev;/etc;/var/tmp;/tmp"

# Additional files to copy to chrooted environment
# /etc/resolv.conf is needed to enable internet access
# /etc/pki/tls/certs/ca-bundle.crt and /etc/pki/tls/certs/ca-bundle.trust.crt are needed to enable SSL certificate verification
FILES_TO_COPY="/etc/localtime;/etc/passwd;/etc/group;/etc/resolv.conf;/etc/pki/tls/certs/ca-bundle.crt;/etc/pki/tls/certs/ca-bundle.trust.crt;/etc/ld.so.conf"

# Default group for chrooted users
#GROUP=chroot
GROUP=apache

# Shell to use in chrooted environment
SHELL=/usr/bin/bash

# ADD chroot entry to ssh server
ADD_SSH_CHROOT_ENTRY=yes

# Use alternative chroot method without SSH (login chroot script)
USE_CHROOT_SCRIPT=no

## END OF STANDARD CONFIGURATION OPTIONS ###########################################################

CHROOT_SCRIPT_PATH=/bin/chrootusers
USER_HOME=/home

# Basic directories present on most linux flavors
BASIC_DIRS="/usr/bin;/usr/lib;/usr/lib64"
# Create symlinks for BASIC_DIRS to root (used on most linux flavors)
CREATE_SYMLINKS="yes"

SSHD_CONFIG="/etc/ssh/sshd_config"

# Prevent cp -i alias that stays interactive
alias cp=cp

function LogDebug
{
	if [ "$DEBUG" == "yes" ]
	then
		echo "$1"
	fi
}

function CheckErr
{
	if [ $? != 0 ]
	then
	exec_error=1
	echo "Failed on task: $1"
	fi
}

function Usage
{
	echo "$PROGRAM build $PROGRAM_BUILD"
	echo $AUTHOR
	echo $CONTACT
	echo ""
	echo "$0 <login> [--alt-chroot-dir=/jail/dir] [--add-program=/path/to/program] [-f]"
	echo "Creates user <login> and sets shell jail to its home directory"
	echo "--add-program=/some/program	Adds a program and its dependencies to an existing chrooted user jail"
	echo "--alt-chroot-dir=/another/home	By default, chroot is created in /home/<login>. You can specify an alternate root here and chroot will be created in <altroot>/<login>"
	echo "					This parameter also triggers a new chrootscript with the alternative home"
	echo "-f 				Forces deletion of existing user and chroot scripts"
	exit 128
}

function CheckEnvironment
{
	case $(uname -m) in

	x86_64)
	ARCH=x64
	LIB="/lib64;/lib"
	;;
	i686)
	ARCH=x86
	LIB=/lib
	;;
	*)
	ARCH=unknown
	;;

	esac

	if [ "$ARCH" == "unknown" ]
	then
		echo "Unknown architecture"
		exit 1
	fi

	if ! type -p bash > /dev/null 2>&1
	then
		echo "Cannot find bash shell environment."
		exit 1
	fi

	if ! type -p env > /dev/null 2>&1
	then
		echo "Cannot find env."
		exit 1
	else
		ENV_BINARY=$(type -p env)
	fi

	if ! type -p chroot > /dev/null 2>&1
	then
		echo "Cannot find chroot executable."
		exit 1
	else
		CHROOT_BINARY=$(type -p chroot)
		CHROOT_BINARY_ALT="$CHROOT_BINARY""_alt"
	fi

	if ! type -p ldd > /dev/null 2>&1
	then
		echo "Cannot find ldd executable."
		exit 1
	fi

	if ! type -p ldconfig > /dev/null 2>&1
	then
		echo "Cannot find ldconfig executable."
		exit 1
	fi

	if ! type -p ln > /dev/null 2>&1
	then
		echo "Cannot find ln executable."
		exit 1
	else
		LN_BINARY=$(type -p ln)
	fi

}

function AddUserAndGroup
{
	echo "Creating group $GROUP"
	groupadd "$GROUP"

	echo "Creating user $LOGIN"
	# Returns 1 if user doesn't exist
	id -nu "$LOGIN" > /dev/null 2>&1
	if [ $? != 0 ] || [ "$force" == "1" ]
	then
		if [ "$USE_CHROOT_SCRIPT" == "yes" ]
		then
			chroot="-s $CHROOT_SCRIPT_PATH"
		else
			chroot=""
		fi
		useradd -c "User chrooted" -d "$CHROOT_DIR/" -g "$GROUP" $chroot "$LOGIN"
		CheckErr "Adding user $LOGIN"
	else
		echo "User $LOGIN already exists."
		exit 1
	fi

	echo "Please enter password for $LOGIN"
	passwd "$LOGIN" > /dev/null
	CheckErr "Creating password for $LOGIN"
	if ! [ -d "$CHROOT_DIR" ]
	then
		echo "Creating home directory"
		mkdir -p "$CHROOT_DIR/"
		CheckErr "Create directory $CHROOT_DIR/"
	fi
}

function AddBinaryPaths
{
	OLD_IFS=$IFS
	IFS=";"
	for binary in $BINARIES_TO_COPY
	do
		DIRS_TO_CREATE="$DIRS_TO_CREATE;$(dirname $binary)"
	done
	IFS=$OLD_IFS
	LogDebug "List of directories to create: $DIRS_TO_CREATE"
}

function CreatePaths
{
	OLD_IFS=$IFS
	IFS=";"
	LogDebug "$DIRS_TO_CREATE"
	for dir in $DIRS_TO_CREATE
	do
		if ! [ -d "$CHROOT_DIR$dir" ]
		then
			LogDebug "Creating $CHROOT_DIR$dir"
			mkdir -p "$CHROOT_DIR$dir"
			CheckErr "Create directory $CHROOT_DIR$dir"
		fi

		chmod 700 "$CHROOT_DIR$dir"
		CheckErr "command chmod 700 $CHROOT_DIR$dir"
	done
	IFS=$OLD_IFS
}

# Adds binaries and dependancy libs to chroot (list separated by semicolons given as argument)
function AddBinaries
{
	OLD_IFS=$IFS
	IFS=";"
	for binary in $1
	do
		dependencies=""
		if [ ! -d "$CHROOT_DIR$(dirname $binary)" ]
		then
			mkdir -p "$CHROOT_DIR$(dirname $binary)"
			CheckErr "Creating $CHROOT_DIR$(dirname $binary)"
		fi

		LogDebug "Copying $binary to $CHROOT_DIR$binary"
		cp $binary "$CHROOT_DIR$binary"
		CheckErr "Copy $binary to $CHROOT_DIR$binary"

		IFS=$OLD_IFS
		# Get all dependant libraries from binary (ldd sometimes gives output at first column and sometimes at third depending on the type of dependency)
		dependencies=$(ldd $binary | awk '{print $1}' | grep "^/")
		dependencies="$dependencies"$'\n'$(ldd $binary | awk '{print $3}' | grep "^/")
		for dependency in $dependencies
		do
			dependency_dir=$(dirname $dependency)
			if [ ! -d "$CHROOT_DIR$dependency_dir" ]
			then
				mkdir -p "$CHROOT_DIR$dependency_dir"
				CheckErr "Creating $CHROOT_DIR$dependency_dir"
			fi

			if [ ! -f "$CHROOT_DIR$dependency" ]
			then
				LogDebug "Copying dependency $dependency to $CHROOT_DIR$dependency_dir/"
				cp "$dependency" "$CHROOT_DIR$dependency_dir/"
				CheckErr "Copy $dependency to $CHROOT_DIR$dependency_dir/"
			fi
		done
		IFS=";"
	done
	IFS=$OLD_IFS
}

function CopyFiles
{
	OLD_IFS=$IFS
	IFS=";"
	for file in $FILES_TO_COPY
	do
		LogDebug "Copying $file to $CHROOT_DIR$(dirname $file)/"
		if ! [ -d "$CHROOT_DIR$(dirname $file)" ]
		then
			mkdir -p "$CHROOT_DIR$(dirname $file)"
			CheckErr "reate $CHROOT_DIR$(dirname $file)"
		fi
		cp "$file" "$CHROOT_DIR$(dirname $file)/"
		CheckErr "Copy $file to $CHROOT_DIR$(dirname $file)/"
	done
	IFS=$OLD_IFS
}

function CopyDirs
{
	OLD_IFS=$IFS
	IFS=";"
	for dir in $EXT_DIRS
	do
		mkdir -p "$CHROOT_DIR$dir"
		CheckErr "Creating $CHROOT_DIR$dir"
		LogDebug "Copying directory $dir to $CHROOT_DIR/"
		cp -R "$dir/" "$CHROOT_DIR$(dirname $dir)"
		CheckErr "Copy $dir to $CHROOT_DIR/"
	done
	IFS=$OLD_IFS
}

function AllowChrootBinary
{
	if [ -f "$CHROOT_BINARY" ]
	then
		cp "$CHROOT_BINARY" "$CHROOT_BINARY_ALT"
		CheckErr "Copy $CHROOT_BINARY to $CHROOT_BINARY_ALT"
		# Setuid for allowing execution of chroot binary by normal user
		chmod 4755 "$CHROOT_BINARY_ALT"
		CheckErr "chmod 4755 $CHROOT_BINARY_ALT"
	fi
}

function AddSSHChrootEntry
{
	if [ -f $SSHD_CONFIG ]
	then
		LogDebug "Adding chroot entry to $SSHD_CONFIG"
		echo "" >> $SSHD_CONFIG
		echo "Match User $LOGIN" >> $SSHD_CONFIG
		echo "	ChrootDirectory $CHROOT_DIR" >> $SSHD_CONFIG
		echo "	AllowTCPForwarding no" >> $SSHD_CONFIG
		echo "	X11Forwarding no" >> $SSHD_CONFIG
		CheckErr "Adding chroot entry to $SSHD_CONFIG"

		echo "Don't forget to reload sshd."
	else
		echo "Cannot find $SSHD_CONFIG path"
		exit 1
	fi
}

function CreateChrootScript
{
	if ! [ -f "$CHROOT_SCRIPT_PATH" ] || [ "$force_script" == "1" ]
	then
		echo "Creating $CHROOT_SCRIPT_PATH"
		cat > "$CHROOT_SCRIPT_PATH" << EXTSCRIPT
#!/bin/bash
if [ -d "$USER_HOME/\$USER" ]
then
	exec -c "$CHROOT_BINARY_ALT" "$USER_HOME/\$USER" "$ENV_BINARY" -i TERM="\$TERM" HOME="/" $SHELL --login -i
else
	echo "No home directory"
	exit 1
fi
EXTSCRIPT
		CheckErr "Create script $CHROOT_SCRIPT_PATH"
		chmod 555 "$CHROOT_SCRIPT_PATH"
		CheckErr "chmod 555 $CHROOT_SCRIPT_PATH"
	else
		echo "$CHROOT_SCRIPT_PATH already exists. Use -f to override."
	fi
}

function AddSymlinks
{
	# Add symlinks from BASIC_DIRS to root dir
	OLD_IFS=$IFS
	IFS=";"

	for link in $BASIC_DIRS
	do
		LogDebug "Creating symlink $link -> /$(basename $link)"
		$LN_BINARY -s "$link" "$CHROOT_DIR/$(basename $link)"
		CheckErr "Creating $link symlink"
	done
	IFS=$OLD_IFS
}

function AddSpecialFiles
{
	if ! [ -c "$CHROOT_DIR/dev/null" ]
	then
		mknod "$CHROOT_DIR/dev/null" c 1 3 -m 666
		CheckErr "Creating /dev/null in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/console" ]
	then
		mknod "$CHROOT_DIR/dev/console" c 5 1 -m 622
		CheckErr "Creating /dev/console in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/zero" ]
	then
		mknod "$CHROOT_DIR/dev/zero" c 1 5 -m 666
		CheckErr "Creating /dev/zero in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/ptmx" ]
	then
		mknod "$CHROOT_DIR/dev/ptmx" c 5 2 -m 666
		CheckErr "Creating /dev/ptmx in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/tty" ]
	then
		mknod "$CHROOT_DIR/dev/tty" c 5 1 -m 666
		CheckErr "Creating /dev/tty in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/random" ]
	then
		mknod "$CHROOT_DIR/dev/random" c 1 8 -m 444
		CheckErr "Creating /dev/random in jail"
	fi

	if ! [ -c "$CHROOT_DIR/dev/urandom" ]
	then
		mknod "$CHROOT_DIR/dev/urandom" c 1 9 -m 444
		CheckErr "Creating /dev/urandom in jail"
	fi

	chown  root:tty $CHOOT_DIR/dev/{console,ptmx,tty}
	CheckErr "Taking ownership of /dev/console /dev/ptmx and /dev/tty"
}

function Runldconfig
{
	LogDebug "Running ldconfig in chrooted environment"
	chroot $CHROOT_DIR /usr/sbin/ldconfig
	CheckErr "ldconfig failed"
}

function SetPermissions
{
	LogDebug "Changing owner of $CHROOT_DIR to $LOGIN:$GROUP"
	chown -R "$LOGIN:$GROUP" "$CHROOT_DIR/"
	CheckErr "chown -R $LOGIN:$GROUP $CHROOT_DIR/"

	chown "root:root" "$CHROOT_DIR"
	CheckErr "chown root:root $CHROOT_DIR"

	chmod 755 "$CHROOT_DIR"
	CheckErr "chmod 755 $CHROOT_DIR"
}

if [ "$1" == "" ]
then
	Usage
else
	LOGIN="$1"
fi

CheckEnvironment

force=0
force_script=0
for i in "$@"
do
	case $i in
	--add-program=*)
	ADD_PROGRAM="${i##*=}"
	;;
	--alt-chroot-dir=*)
	USER_HOME="${i##*=}"
	force_script=1
	;;
	-f)
	force=1
	force_script=1
	;;
	esac
done
CHROOT_DIR="$USER_HOME/$LOGIN"

# Add arch dependend lib path to directory list
DIRS_TO_CREATE="$DIRS_TO_CREATE;$CHROOT_DIR"

if ! [ "$ADD_PROGRAM" == "" ]
	then
	AddBinaryPaths
	CreatePaths
	AddBinaries "$ADD_PROGRAM"
	SetPermissions
	exit
else
	# Normal program run
	AddUserAndGroup
	CreatePaths
	CopyDirs
	CopyFiles
	if [ "$CREATE_SYMLINKS" == "yes" ]
	then
		AddSymlinks
	fi
	AddBinaries "$SHELL;$ENV_BINARY;$BINARIES_TO_COPY"
	if [ "$ADD_SSH_CHROOT_ENTRY" == "yes" ]
	then
		AddSSHChrootEntry
	fi
	if [ "$USE_CHROOT_SCRIPT" == "yes" ]
	then
		AllowChrootBinary
		CreateChrootScript
	fi
	AddSpecialFiles
	Runldconfig
	SetPermissions
fi

if [ "$exec_error" == "1" ]
then
	echo "Script finished with errors for user $LOGIN"
else
	echo "Created chrooted user $LOGIN"
fi
