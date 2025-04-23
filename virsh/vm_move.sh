#!/usr/bin/env bash

# Quick and dirty KVM VM local storage move script
# Written by Orsiris de Jong
# Usage
# ./vm_move.sh vm_name destination_path [dryrun=true|false]
SCRIPT_BUILD=2025042401

# SCRIPT ARGUMENTS
VM_NAME="${1:-false}"
DST_DIR="${2:-false}"
DRY_RUN="${3:-false}"
DELETE_SOURCE="${4:-false}"


LOG_FILE="/var/log/$(basename $0).log"


SCRIPT_GOOD=true

log() {
    __log_line="${1}"
    __log_level="${2:-INFO}"

    __log_line="${__log_level}: ${__log_line}"
    echo "${__log_line}" >> "${LOG_FILE}"
    echo "${__log_line}"

    if [ "${__log_level}" = "ERROR" ]; then
        SCRIPT_GOOD=false
    fi
}


move_storage() {
        # Filter disk images only
        xml_dumped=false
        xml_ok=false
        disk_pivoted=false
        vm_xml="${DST_DIR}/${VM_NAME}.inactive.$(date +"%Y%m%dT%H%M%S").xml"
        for disk in $(virsh domblklist "$VM_NAME" --details | grep "file" | grep "disk" | awk '{print $3"="$4}'); do
                disk_name="$(echo "${disk}" | awk -F'=' '{print $1}')"
                src_disk_path="$(echo "${disk}" | awk -F'=' '{print $2}')"
                if [ ! -f "${src_disk_path}" ]; then
                        log "Source disk ${disk_name} not found in ${src_disk_path}" "ERROR"
                        break
                fi
                dst_disk_path="${DST_DIR}/$(basename "${src_disk_path}")"
                log "Found disk ${disk_name} in ${src_disk_path}"
                if [ "${xml_dumped}" == false ]; then
                        log "Exporting ${VM_NAME} to ${vm_xml}"
                        virsh dumpxml --inactive "${VM_NAME}" > "${vm_xml}"
                        if [ $? != 0 ]; then
                                log "VM $VM_NAME dump failed. Not trying to migrate it" "ERROR"
                                break
                        else
                                xml_dumped=true
                                xml_ok=true
                        fi
                        log "Undefining $vm_name"
                        [ "${DRY_RUN}" == true ] || virsh undefine "${VM_NAME}"
                        if [ $? != 0 ]; then
                                log "Undefining $VM_NAME failed" "ERROR"
                                break
                        fi
                fi
                log "Moving disk ${disk_name} to ${dst_disk_path}"
                [ "${DRY_RUN}" == true ] || virsh blockcopy "${VM_NAME}" "${disk_name}" --dest="${dst_disk_path}" --wait --pivot --verbose
                if [ $? != 0 ]; then
                        log "Failed to blockcopy $VM_NAME to $DST_DIR/$vm_disk" "ERROR"
                        disk_pivoted=false
                        break
                else
                        # Check if disk image is not in use anymore
                        lsof "${src_disk_path}" > /dev/null 2>&1
                        if [ $? -eq 0 ]; then
                                log "Disk ${src_disk_path} is still in use by $(lsof "${src_disk_path}")" "ERROR"
                        else
                                disk_pivoted=true
                                if [ "${DELETE_SOURCE}" == true ]; then
                                log "Deleting source disk ${src_disk_path}"
                                else
                                        old_disk_path="${src_disk_path}.old.$(date +"%Y%m%dT%H%M%S")"
                                        log "Renaming original file to ${old_disk_path}"
                                        mv "${src_disk_path}" "${old_disk_path}" || log "Cannot rename old disk image" "ERROR"
                                fi
                        fi
                fi
                log "Modifying disk path from \"${src_disk_path}\" to \"${dst_disk_path}\""
                sed -i "s#${src_disk_path}#${dst_disk_path}#g" "${vm_xml}"
                if [ $? != 0 ]; then
                        log "Failed to modify XML file $vm_vml" "ERROR"
                        if [ "${disk_pivoted}" == false ]; then
                                log "Stopping operation since disks did not pivot yet"
                                 break
                        else
                                log "Continuing operations, but xml file is bad" "ERROR"
                                xml_ok=false
                        fi
                fi
                if ! grep "${dst_disk_path}" "$vm_xml" > /dev/null 2>&1; then
                        log "XML file check did not succeed" "ERROR"
                        xml_ok=false
                fi
        done

        if [ "${xml_ok}" == true ]; then
                log "Defining VM ${VM_NAME} from ${vm_xml}"
                [ "${DRY_RUN}" == true ] || virsh define "$vm_xml"
                if [ $? != 0 ]; then
                       log "Failed to redefine ${VM_NAME}" "ERROR"
                fi
        else
                log "XML file is not okay, cannot redefine ${VM_NAME} from ${vm_xml}" "ERROR"
                log "VM ${VM_NAME} is in transient state. Please repair." "ERROR"
        fi
}


[ "${DRY_RUN}" == true ] && log "Running in DRY mode. Nothing will actually be done" "NOTICE"

if [ "${VM_NAME}" == "" ] || [ "${DST_DIR}" == "" ]; then
        log "Please run $0 [vm_name] [dest_dir]"
        exit 1
fi

DST_DIR="$(realpath "${DST_DIR}")"

[ ! -d "${DST_DIR}" ] && mkdir "${DST_DIR}"
if [ ! -w "${DST_DIR}" ]; then
        log "Destination dir ${DST_DIR} is not writable" "ERROR"
        exit 1
fi

if ! virsh list --name | grep "^${VM_NAME}$" > /dev/null 2>&1; then
        log "VM ${VM_NAME} not found via virsh list" "ERROR"
        exit 1
fi

move_storage "${VM_NAME}" "${DST_DIR}"


log "List of transient domains"
virsh list --transient
virsh list --transient >> "$LOG_FILE" 2>&1

log "End of line"

if [ "${SCRIPT_GOOD}" == true ]; then
        exit 0
else
        exit 1
fi
