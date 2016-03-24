#!/usr/bin/env bash

PROGRAM="ddsplit.sh" # Quick and dirty command to backup / restore disk / data using dd and compress & split backup files
AUTHOR="(L) 2016 by Orsiris de Jong"
CONTACT="http://www.netpower.fr - ozy@netpower.fr"
PROGRAM_VERSION=0.1-stable
PROGRAM_BUILD=2016032302

# Let dd error impact the whole pipe command
set -o pipefail

filesPrefix="ddsplit"
filesPrefixLength=${#filesPrefix}

function Backup {
	local dd_cmd_result=0
	local splitNumber=0
	local filenameSplit=main

	while [ "$dd_cmd_result" == 0 ]
	do
		cmd="dd if=\"$source\" bs=$splitSize count=1 skip=$splitNumber iflag=fullblock,direct | pigz --fast > \"$FILEPATH/$filesPrefix.$splitSize.$filenameSplit.$FILENAME.gz\""
		echo "$cmd"
		eval "$cmd"
		dd_cmd_result=$?
		splitNumber=$((splitNumber + 1))
		filenameSplit=$splitNumber
	done
}

function Restore {
	local splitSize
	local splitNumber
	local fileToRestore
	local filenameSuffix

	if [ "${FILENAME:0:$filesPrefixLength}" != "$filesPrefix" ]; then
		echo "Source file does not seem to be a $PROGRAM generated file."
		exit 1
	fi

	# Remove  prefix
	filenameSuffix="${FILENAME#$filesPrefix.*}"
	# Get splitsize
	splitSize="${filenameSuffix%%.*}"
	# Remove split size
	filenameSuffix="${filenameSuffix#*.}"
	# Get split number
	splitNumber="${filenameSuffix%%.*}"
	# Remove split number
	filenameSuffix="${filenameSuffix#*.}"

	fileToRestore="$FILEPATH/$filesPrefix.$splitSize.$splitNumber.$filenameSuffix"
	while [ -f "$fileToRestore" ]
	do
		if [ "$splitNumber" == "main" ]; then
			splitNumber=0
		fi
		cmd="pigz -dc \"$fileToRestore\" | dd of=\"$destination\" bs=$splitSize seek=$splitNumber"
		echo "$cmd"
		eval "$cmd"
		splitNumber=$((splitNumber + 1))
		filenameSplit=$splitNumber
		fileToRestore="$FILEPATH/$filesPrefix.$splitSize.$filenameSplit.$filenameSuffix"
	done
}

function CutFileNames {
	local filename="${1}"

	FILENAME="${filename##*/}"
	FILEPATH="${filename%/*}"
	if [ "$FILEPATH" == "" ] || [ "$FILEPATH" == "$FILENAME" ]; then
		FILEPATH="."
	fi
}

function Usage {
	echo "$PROGRAM - Low tech script to backup / restore with dd into compressed and splitted files"
	echo "$AUTHOR"
	echo "$CONTACT"
	echo ""
	echo "ATTENTION: This program may destroy all your data if used wrong. Use at your own risk !"
	echo ""
	echo "Usage:"
	echo "$PROGRAM --backup [source] [destination] [splitsize]"
	echo "         Produces files called $filesPrefix.splitsize.splitnumber.destination.gz"
	echo "         splitsize is optional and works just like dd does (eg 1K, 1M, 1G...). Maximum is 1G (default value is 1G)."
	echo "$PROGRAM --restore [source] [destination]"
	echo "         Source needs to be the first split file called $filesPrefix.splitsize.master.somename.gz"
	exit 128
}

command="$1"
source="$2"
destination="$3"
splitSize="${4:-1G}"

if ([ "$source" == "" ] || [ "$destination" == "" ]); then
	Usage
fi

if [ "$command" == "--backup" ]; then
	CutFileNames "$destination"
	Backup
fi

if [ "$command" == "--restore" ]; then
	CutFileNames "$source"
	Restore
fi

if [ "$command" == "--version" ] ||[ "$command" == "-v" ]; then
	Usage
fi
