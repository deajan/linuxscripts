#!/usr/bin/env bash

PROGRAM="repairbadsectors"
AUTHOR="Orsiris de Jong & Frederick Fouquet"
VERSION=0.1
PROGRAM_BUILD=2016050701

function Usage {
echo "Repair bad blocks from hard disk"
echo "CAUTION: Use at your own risk, repair attempts are non destructive but a mechanic disk may totally fail under stress."
echo "Always make nice backups first !"
echo ""
echo "This script has 3 different bad block correction functions:"
echo "dd intelligent repair:"
echo "    Makes a list of all bad sectors with [badblock], then read the sectors to a tmp file, zero fill them, and write the data back from the tmp file."
echo ""
echo "hdparm repair:"
echo "    Makes a list of all bad sectors with [badblock], then reads them with hdparm, and tries to write them on read failure."
echo ""
echo "dd dumb repair:"
echo "    Same as dd intelligent repair, but instead of reading a list of bad sectors, proceeds for all sectors or a sector span."
echo ""
echo "Procedure explanation:"
echo ""
echo "Whenever a block of 4KB (8x512B sectors) is written to a disk, the disk firmware reallocates the sector if the sector is marked bad."
echo "Warning: both dd intelligent repair and hdparm repair may not find bad sectors to repair if they are in \"current pending\" SMART status"
echo "as the badblock utility won't see them."
echo "dd dumb repair will find them, but will take painfully long to cover the whole disk."
echo "dd dumb repair should be used to cover areas of the disk."
echo ""
echo "Usage:"
echo "./repairbadblocks.sh /dev/sdX /tmp/directory"
echo "/dev/sdX is the disk you want to repair"
echo "/tmp/directory is a temporary directory containing sector data and bad blocks lists. Make sure it is a ramdrive or another disk than the one your're trying to repair."
exit 1
}

#Todo real menu
#Todo spinner

function isNumeric {
        eval "local value=\"${1}\"" # Needed so variable variables can be processed

        local re="^-?[0-9]+([.][0-9]+)?$"
        if [[ $value =~ $re ]]; then
                echo 1
        else
               	echo 0
        fi
}

function readBadBlocks {
	local drive="${1}"
	local tmp_dir="${2}"

	echo "Reading bad blocks from $drive"
	badblocks -b 4096 -c 8 -sv -o "$tmp_dir/badblocks.$(basename $drive)" $drive
}

#Todo function readWriteNonDestructiveBadBlocks
#function readWriteDestructiveBadBlocks

function hdparmRepair {
	local drive="${1}"
	local tmp_dir="${2}"
	local lbablock="${3}"

	local badblockscount
	local counter=0
	local block
	local sector_begin
	local sector_end
	local result

	# Todo, what output does badblocks provide ?
	# Todo specific lbablock or badblocks
	readBadBlocks "$drive" "$tmp_dir"
	badblockscount=$(wc -l < "$tmp_dir/badblocks.$(basename $drive)")

	while read $block; do
		echo "Reading sector $block ($counter / $badblockscount)"
		sector_begin=$((block*8))
		sector_end=$((sector_begin+7))
		for sector in $(seq $sector_begin $sector_end); do
			hdparm --read-sector $sector $drive > /dev/null
			result=$?
			if [ $result -eq 0 ]; then
				echo "Sector [$sector] seems okay."
			elif [ $result -eq 5 ]; then
				echo "Sector [$sector] seems bad. Trying to rewrite it with zeros."
				hdparm --write-sector $sector --yes-i-know-what-i-am-doing $drive
			elif [ $result -eq 19 ]; then
				echo "Missing disk [$drive]."
				exit 2
			elif [ $result -eq 25 ]; then
				echo "Guru meditation failure with guru code [$result]."
				exit 3
			fi
		done
		counter=$((counter+1))
	done < "$tmp_dir/badblocks.$(basename $drive)"
	echo "Finished repairs. Please do a smart long test on drive [$drive]."
	exit 0
}

function ddIntelligentRepair {
	local drive="${1}"
	local tmp_dir="${2}"
	local lbablock="${3}"

	local badblockscount
	# TODO lbablock or readBadBlocks
	readBadBlocks "$drive" "$tmp_dir"
	badblockscount=$(wc -l < "$tmp_dir/badblocks.$(basename $drive)")

	while read $block; do
		echo "Trying to repair block [$block] ($counter / $badblockscount)."
		sector=$((block*8))
		dd if=$drive iflag=direct of="$tmp_dir/badblock.$sector.$(basename $drive)" bs=4096 count=1 skip=$sector > /dev/null
		dd if=/dev/zero of=$drive oflag=direct bs=4096 count=1 skip=$sector > /dev/null
		dd if="$tmp_dir/badblock.$block.$(basename $drive)" of=$drive oflag=direct bs=4096 count=1 skip=$sector > /dev/null
		if [ $? == 0 ]; then
			rm -f "$tmp_dir/badblock.$block.$(basename $drive)"
		else
			echo "Failed to dd write block [$block]."
		fi
		counter=$((counter+1))
	done < "$tmp_dir/badblocks.$(basename $drive)"
	echo "Finished repairs. Please do a smart long test on drive [$drive]."
	exit 0
}


function ddDumbRepair {
	local drive="${1}"
	local tmp_dir="${2}"

	local block=0
	local read_result=0
	local continue=true

	local begin_block=0
	local end_block=0

	read -r -p "Beginning block number (0) ? " begin_block
	read -r -p "Ending block number (end of disk) ?" end_block

	if [ $(isNumeric "$begin_block") -eq 1 ]; then
		block=$begin_block
	fi

	if [ $(isNumeric "$end_block") -eq 0 ]; then
		end_block=0
	fi

	while [ $continue == true ]; do
		dd if=$drive iflag=direct of="$tmp_dir/badblock.tmp.$(basename $drive)" bs=4096 count=1 skip=$block > /dev/null 2>&1
		read_result=$?
		dd if=/dev/zero of=$drive oflag=direct bs=4096 count=1 skip=$block > /dev/null 2>&1
		dd if="$tmp_dir/badblock.tmp.$(basename $drive)" of=$drive oflag=direct bs=4096 count=1 skip=$block > /dev/null 2>&1
		block=$((block+1))
		if [ $((block % 1000)) -eq 0 ]; then
			echo "Processed [$block] blocks."
		fi
		if [ $end_block -ne 0 ] && [ $block -gt $end_block ]; then
			continue=false
		elif [ $end_block -eq 0 ] && [ $read_result -ne 0 ]; then
			continue=false
		fi
	done
	exit 0
}

function confirmation {
	read -r -p "Are you sure to proceed (yes/NO) ?" ack
	if [ "$ack" == "yes" ] || [ "$ack" == "YES" ]; then
		return 1
	else
		return 0
	fi
}

function checkEnvironnment {

	if type dd > /dev/null 2>&1; then
		DD_PRESENT=true
	else
		echo "[dd] not found, will not provide dd repair options."
		DD_PRESENT=false
	fi

	if type badblocks > /dev/null 2>&1; then
		BADBLOCKS_PRESENT=true
	else
		echo "[badblocks] not found, repair time will be *much* longer."
		BADBLOCKS_PRESENT=false
	fi

	if type hdparm > /dev/null 2>&1; then
		hdparm_ver=$(hdparm -V | cut -f2 -d'v')
		if [ $(bc <<< "$hdparm_ver>=8.0") -eq 1 ]; then
			HDPARM_PRESENT=true
		else
			echo "[hdparm] needs to be >= v8.0 to support repairs. Will not provide hdparm repair option."
			HDPARM_PRESENT=false
		fi
	else
		echo "[hdparm] not found, will not provide hdparm repair option."
	fi

	if ([ $DD_PRESENT == false ] && ([ $BADBLOCKS_PRESENT == false ] || [ $HDPARM_PRESENT == false ])); then
		echo "No required repair tools found. Cannot continue."
		exit 1
	fi
}

if [ "$1" != "" ] && [ "$2" != "" ]; then
	if [ ! -w "$1" ] || [ ! -w "$2" ]; then
	Usage
	else
		DRIVE="$1"
		TMP_DIR="$2"
	fi
else
	Usage
fi

checkEnvironnment

if ([ $DD_PRESENT == true ] && [ $BADBLOCKS_PRESENT == true ]); then
	echo "Launch intelligent dd repair"
	confirmation
	if [ $? -eq 1 ]; then
		ddIntelligentRepair "$DRIVE" "$TMP_DIR"
	fi
fi

if ([ $HDPARM_PRESENT == true ] && [ $BADBLOCKS_PRESENT == true ]); then
	echo "Launch hdparm repair"
	confirmation
	if [ $? -eq 1 ]; then
		hdparmRepair "$DRIVE" "$TMP_DIR"
	fi
fi

if [ $DD_PRESENT == true ]; then
	echo "Launch dumb dd repair (painfully long)"
	confirmation
	if [ $? -eq 1 ]; then
		ddDumbRepair "$DRIVE" "$TMP_DIR"
	fi
fi

echo "No option selected."
exit 0

