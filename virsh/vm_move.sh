#!/usr/bin/env bash

# Quick and dirty VM local storage move script
SCRIPT_BUILD=2025032601

SRC_DIR=/data/private_vm
DST_DIR=/data/public_vm/npf
DISK_SUFFIX="-disk0.qcow2"
LOG_FILE="/var/log/$(basename $0).log"
DRY_RUN=false


log() {
    __log_line="${1}"
    __log_level="${2:-INFO}"

    __log_line="${__log_level}: ${__log_line}"
    echo "${__log_line}" >> "${LOG_FILE}"
    echo "${__log_line}"
}

for vm_disk in $(find $SRC_DIR -mindepth 1 -maxdepth 1 -iname "*${DISK_SUFFIX}" -type f -printf "%f\n"); do
        log Found $vm_disk
        vm_name="${vm_disk:0:-${#DISK_SUFFIX}}"
        vm_xml="$SRC_DIR/$vm_name.inactive.xml"
        log "Trying to extrapolate corresponding VM with $vm_name"
        virsh dumpxml --inactive $vm_name > "$vm_xml"
        if [ $? != 0 ]; then
                log "VM $vm_name dump failed. Not trying to migrate it" "ERROR"
                continue
        fi
        log "Undefining $vm_name"
        [ "${DRY_RUN}" == true ] || virsh undefine $vm_name
        if [ $? != 0 ]; then
                log "Undefining $vm_name failed" "ERROR"
                continue
        fi
        # Would require getting all disks
        log "Moving $vm_name to $DST_DIR/$vm_disk"
        [ "${DRY_RUN}" == true ] || virsh blockcopy $vm_name vda --dest=$DST_DIR/$vm_disk --wait --pivot --verbose
        if [ $? != 0 ]; then
                log "Failed to blockopty $vm_name to $DST_DIR/$vm_disk" "ERROR"
                continue
        fi
        sed -i "#$SRC_DIR#$DST_DIR#g" "$vm_xml"
        [ "${DRY_RUN}" == true ] || virsh define $vm_xml
        if [ $? != 0 ]; then
                log "Failed to redefine $vm_name" "ERROR"
                continue
        fi
done

log "List of transient domains"
virsh list --transient
virsh list --transient >> "$LOG_FILE" 2>&1

log "End of line"
