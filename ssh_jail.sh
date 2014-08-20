#!/usr/bin/env bash

PROGRAM="ssh_jail.sh" # Basic ssh shell jail creation script
AUTHOR="(L) 2014 by Orsiris \"Ozy\" de Jong"
CONTACT="http://www.netpower.fr - ozy@netpower.fr"
PROGRAM_BUILD=2008201401

## Creates a SSH chroot jail where a given user can login and execute a minimal set of programs
## Binaries specified by BINARIES_TO_COPY will be available
## You may also specifiy /usr/bin and /lib in EXT_DIRS to gain multiple binaries

## If you need support for editing programs, consider adding /usr/share/terminfo (CentOS) or /lib/terminfo directories (Debian) to EXT_DIRS


# List of binary files to copy to chrooted environment. All dependencies will also be copied.
BINARIES_TO_COPY="/usr/bin/chmod;/usr/bin/chown;/usr/bin/ls;/usr/bin/cat;/usr/bin/ln;/usr/bin/cp" # Works on CentOS 7
#BINARIES_TO_COPY="/bin/chmod;/bin/chown;/bin/ls;/bin/cat;/bin/ln;/bin/cp;/bin/mv;/bin/rm;/usr/bin/curl" # Works on Debian 6

# Directories to copy to chrooted environment
EXT_DIRS="/usr/bin;/lib64;/usr/share/php;/usr/share/terminfo;/usr/include" # Works on CentOS 7 (replace lib by lib64 if needed)
#EXT_DIRS="/bin;/lib;/lib/terminfo" # Works on Debian 6 (replace lib by lib64 if needed)
#EXT_DIRS="/lib/terminfo"

# Empty directories to create in chrooted environment types (lib and lib64 directories are already included)
DIRS_TO_CREATE="/dev;/etc;/var;/tmp"

# Additional files to copy to chrooted environment
FILES_TO_COPY="/etc/localtime;/etc/nsswitch.conf;/etc/passwd;/etc/group;/etc/resolv.conf"

# Default group for chrooted users
#GROUP=chroot
GROUP=apache

# Shell to use in chrooted environment
SHELL=/bin/bash

## END OF STANDARD CONFIGURATION OPTIONS ###########################################################

CHROOT_SCRIPT=/bin/chrootusers
USER_HOME=/home

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
	LIB=/lib64;/lib
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
		useradd -c "User chrooted" -d "$CHROOT_DIR/" -g "$GROUP" -s "$CHROOT_SCRIPT" "$LOGIN"
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

function CreateChrootScript
{
	if ! [ -f "$CHROOT_SCRIPT" ] || [ "$force_script" == "1" ]
	then
		echo "Creating $CHROOT_SCRIPT"
		cat > "$CHROOT_SCRIPT" << EXTSCRIPT
#!/bin/bash
if [ -d "$USER_HOME/\$USER" ]
then
	exec -c "$CHROOT_BINARY_ALT" "$USER_HOME/\$USER" "$ENV_BINARY" -i TERM="\$TERM" HOME="/" $SHELL --login -i
else
	echo "No home directory"
	exit 1
fi
EXTSCRIPT
		CheckErr "Create script $CHROOT_SCRIPT"
		chmod 555 "$CHROOT_SCRIPT"
		CheckErr "chmod 555 $CHROOT_SCRIPT"
	else
		echo "$CHROOT_SCRIPT already exists. Use -f to override."
	fi
}

function AddSpecialFiles
{
	# Add /dev/null special file
	if ! [ -c "$CHROOT_DIR/dev/null" ]
	then
		mknod "$CHROOT_DIR/dev/null" c 1 3 -m 666
		CheckErr "Creating /dev/null in jail"
	fi

	# Add /dev/urandom for ssl support (yeah, how to find this dependency uh ?)
	if ! [ -c "$CHROOT_DIR/dev/urandom" ]
	then
		mknod "$CHROOT_DIR/dev/urandom" c 1 9 -m 644
		CheckErr "Creating /dev/urandom in jail"
	fi
}

function SetPermissions
{
	LogDebug "Changing owner of $CHROOT_DIR to $LOGIN:$GROUP"
	chown -R "$LOGIN:$GROUP" "$CHROOT_DIR"
	CheckErr "chown -R $LOGIN:$GROUP $CHROOT_DIR"
}

if [ "$1" == "" ]
then
	Usage
else
	LOGIN="$1"
fi

CheckEnvironment

# Add arch dependend lib path to directory list
DIRS_TO_CREATE="$DIRS_TO_CREATE;$LIB"

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
	AddBinaries "$SHELL;$ENV_BINARY;$BINARIES_TO_COPY"
	CopyDirs
	CopyFiles
	AllowChrootBinary
	CreateChrootScript
	AddSpecialFiles
	SetPermissions
fi

if [ "$exec_error" == "1" ]
then
	echo "Script finished with errors for user $LOGIN"
else
	echo "Created chrooted user $LOGIN"
fi
