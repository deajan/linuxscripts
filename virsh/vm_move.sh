#!/usr/bin/env bash

# Quick and dirty KVM VM local storage move script
# Written by Orsiris de Jong
# Usage
# ./vm_move.sh vm_name destination_path [dryrun=true|false]
SCRIPT_BUILD=2025042101

# SCRIPT ARGUMENTS
VM_NAME="${1:-false}"
DST_DIR="${2:-false}"
DRY_RUN="${3:-false}"



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
        xml_written=false
        for disk in $(virsh domblklist "$VM_NAME" --details | grep "file" | grep "disk" | awk '{print $3"="$4}'); do
                disk_name="$(echo "${disk}" | awk -F'=' '{print $1}')"
                src_disk_path="$(echo "${disk}" | awk -F'=' '{print $2}')"
                if [ ! -f "${src_disk_path}" ]; then
                        log "Source disk ${disk_name} not found in ${src_disk_path}" "ERROR"
                        break
                fi
                dst_disk_path="$(realpath "${DST_DIR}")/$(basename "${src_disk_path}")"
                log "Found disk ${disk_name} in ${src_disk_path}"
                vm_xml="$(dirname "${dst_disk_path}")/${VM_NAME}.inactive.$(date +"%Y%m%dT%H%M%S").xml"
                if [ "${xml_written}" == false ]; then
                        log "Exporting ${VM_NAME} to ${vm_xml}"
                        virsh dumpxml --inactive "${VM_NAME}" > "${vm_xml}"
                        if [ $? != 0 ]; then
                                log "VM $VM_NAME dump failed. Not trying to migrate it" "ERROR"
                                break
                        else
                                xml_written=true
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
                        log "Failed to blockopty $VM_NAME to $DST_DIR/$vm_disk" "ERROR"
                        break
                fi
                log "Modifying disk path from \"${src_disk_path}\" to \"${dst_disk_path}\""
                sed -i "s#${src_disk_path}#${dst_disk_path}#g" "$vm_xml"
                if [ $? != 0 ]; then
                        log "Failed to modify XML file $vm_vml" "ERROR"
                        break
                fi
        done

        log "Defining VM ${VM_NAME} from ${vm_xml}"
        [ "${DRY_RUN}" == true ] || virsh define $vm_xml
        if [ $? != 0 ]; then
                log "Failed to redefine $VM_NAME" "ERROR"
        fi

        if [ "${SCRIPT_GOOD}" == true ]; then
                log "Renaming original file to ${src_disk_path}.old.$(date +"%Y%m%dT%H%M%S")"
                mv "${src_disk_path}" "${src_disk_path}.old.$(date +"%Y%m%dT%H%M%S")" || log "Cannot rename old disk image" "ERROR"
        fi
}


[ "${DRY_RUN}" == true ] && log "Running in DRY mode. Nothing will actually be done" "NOTICE"

if [ "${VM_NAME}" == "" ] || [ "${DST_DIR}" == "" ]; then
        log "Please run $0 [vm_name] [dest_dir]"
        exit 1
fi

[ ! -d "${DST_DIR}" ] && mkdir "${DST_DIR}"

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
