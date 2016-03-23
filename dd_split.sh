#!/usr/bin/env bash

PROGRAM="dd_split.sh" # Quick and dirty dd command to backup / restore, compress and split backup files
AUTHOR="(L) 2016 by Orsiris de Jong"
CONTACT="http://www.netpower.fr - ozy@netpower.fr"
PROGRAM_VERSION=0.1-dev
PROGRAM_BUILD=2016032302

# Let dd error impact the whole pipe command
set -o pipefail

function Backup {
	local dd_result=0
	local split=0
	local filenameSplit=main
	while [ $dd_result == 0 ]
	do
		cmd="dd if=\"$source\" bs=$splitSize count=1 skip=$split | $COMPRESSION_PROGRAM --fast > \"$dd_FilePath/dd_split.$splitSize.$filenameSplit.$dd_Filename.gz\""
		echo $cmd
		eval $cmd
		dd_result=$?
		split=$((split + 1))
		filenameSplit=$split
	done
}

function Restore {
	local splitSize
	local split
	local fileToRecover

	if [ ${dd_Filename:0:8} != "dd_split" ]; then
		echo "Source file does not seem to be a dd_split file."
		exit 1
	fi

	# Remove "dd_split" prefix
	dd_Filename="${dd_Filename#dd_split.*}"
	# Get splitsize
	splitSize="${dd_Filename%%.*}"
	# Remove split size
	dd_Filename="${dd_Filename#*.}"
	# Get split number
	split="${dd_Filename%%.*}"
	# Remove split number
	dd_Filename="${dd_Filename#*.}"

	fileToRecover="$dd_FilePath/dd_split.$splitSize.$split.$dd_Filename"
	while [ -f "$fileToRecover" ]
	do
		if [ "$split" == "main" ]; then
			split=0
		fi
		cmd="$COMPRESSION_PROGRAM -dc "$fileToRecover" | dd of=\"$destination\" bs=$splitSize seek=$split"
		echo $cmd
		eval $cmd
		split=$((split + 1))
		fileToRecover="$dd_FilePath/dd_split.$splitSize.$split.$dd_Filename"
	done

	# for i in {0..120}; do pigz -dc file.$i.gz | dd of=/dev/sda bs=1G seek=$i; done
}

function FileNames {
	local filename="${1}"

	dd_Filename="${filename##*/}"
	dd_FilePath="${filename%/*}"
	if [ "$dd_FilePath" == "" ] || [ "$dd_FilePath" == "$dd_Filename" ]; then
		dd_FilePath="."
	fi
}

function Usage {
	echo "dd_split - Low tech script backup / restore with dd to compressed and splitted files"
	echo ""
	echo "Usage:"
	echo "dd_split --backup [source] [destination] [splitsize]"
	echo "dd_split --restore [source] [destination] [splitsize]"
	echo "splitsize is optional and works just like dd does."
	echo "To restore, select the source file with \"main\" as split number."
	exit 128
}

if type pigz > /dev/null; then
	COMPRESSION_PROGRAM=pigz
elif type gzip > /dev/null; then
	COMPRESSION_PROGRAM=gzip
else
	echo "No compression program available (need pigz or gzip)."
	exit 1
fi

command="$1"
source="$2"
destination="$3"
splitSize="${4:-1G}"

if ([ "$source" == "" ] || [ "$destination" == "" ]); then
	Usage
fi

if [ $command == "--backup" ]; then
	FileNames "$destination"
	Backup
fi

if [ $command == "--restore" ]; then
	FileNames "$source"
	Restore
fi
