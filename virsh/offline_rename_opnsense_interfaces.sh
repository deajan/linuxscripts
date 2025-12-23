#!/usr/bin/env bash

# This is a script to modify interfaces inside a qcow2 image of OPNsense
# Basically, when restored to another KVM hypervisor, we must update interface names if network card driver names change
# The key here is the sed line which updates known interface names with new ones
# This has been tested on a lagg interface with two members

SCRIPT_BUILD=2025122301

OPNSENSE_VM="opnsense01p.domain.local"
VM_XML="/opt/cube/opnsense01p.domain.local.xml"

# Path to opnsense config.xml file in OPNSense filesystem root
CONF_FILE="/conf/config.xml"
# OPNSense zpool name
ZPOOL="zroot"
# OPNsense zfs dataset mapped to /
ZROOT="zroot/ROOT/default"
# Mountpoint to local filesystem
MOUNT_POINT="/tmp/opnsense_zroot"
# Device name where to mount qcow2 image
DEV=/dev/nbd0
# Path to qcow2 image
DISK_IMAGE="/data/opnsense01p.domain.local-disk0.qcow2"
# Current interface names (can be a space separated list of interfaces
INTERFACES_TO_REPLACE=(ixl[0-9],ixl[0-9])
INTERFACES_REPLACEMENT=(igb0,igb1,igb2,igb3,igb4)

# Aribtrary sleep time in seconds for nbd & zpool operations to succeed
SLEEP_TIME=5

# timeout before forcing VM to go off (seconds)
VM_SHUTDOWN_TIMEOUT=300

LOG_FILE=/var/log/"$(basename "$0.log")"

# Make sure virsh output is english
export LANG=C

# script variables
POST_INSTALL_SCRIPT_GOOD=true
VM_RUNNING=true

ZFS_BINARY=$(type -p zfs)
ZPOOL_BINARY=$(type -p zpool)
VIRSH_BINARY=$(type -p virsh)
QEMU_NBD_BINARY=$(type -p qemu-nbd)


log() {
    __log_line="${1}"
    __log_level="${2:-INFO}"

    __log_line="$(date):${__log_level}: ${__log_line}"
    echo "${__log_line}" >> "${LOG_FILE}"
    echo "${__log_line}"

    if [ "${__log_level}" = "ERROR" ]; then
        POST_INSTALL_SCRIPT_GOOD=false
    fi
}

log_quit() {
    log "${1}" "${2}"
    log "Exiting script"
    exit 1
}

CleanUp() {
        # Check if zroot is currently mounted
        if ${ZPOOL_BINARY} list "${ZPOOL}"; then
                while true; do
                        if mount | grep "${ZROOT}" > /dev/null 2>&1; then
                                log "Unmounting dataset ${ZROOT}"
                                ${ZFS_BINARY} umount "${ZROOT}" 2>> "${LOG_FILE}" || log "Cannot unmount ${ZROOT}" "ERROR"
                        else
                                log "zfs dataset ${ZROOT} is now unmounted"
                                break
                        fi
                done
                sleep ${SLEEP_TIME}
                # very important, we have to make sure zroot is unmounted before setting mountpoint back to / in order to avoid
                # overwriting current OS
                log "Setting zpool ${ZROOT} mountpoint back to /"
                ${ZFS_BINARY} set mountpoint=/ ${ZROOT} 2>> "${LOG_FILE}" || log "Cannot set / as mountpoint on ${ZROOT}" "ERROR"
                log "Exporting zpool ${ZPOOL}"
                ${ZPOOL_BINARY} export "${ZPOOL}" 2>> "${LOG_FILE}" || log "Cannot export ${ZPOOL}" "ERROR"
                while true; do
                        if ${ZPOOL_BINARY} status | grep "${ZROOT}" > /dev/null 2>&1; then
                                log "Waiting for zpool export"
                        else
                                log "zpool ${ZROOT} is now exported"
                                break
                        fi
                        sleep ${SLEEP_TIME}
                done
        else
                log "zpool ${ZPOOL} is not imported"
        fi

        log "Current zpool status"
        ${ZPOOL_BINARY} status
        ${ZPOOL_BINARY} status >> "${LOG_FILE}" 2>&1

        if cmp -n 512 /dev/nbd0 /dev/zero 2>&1 | grep EOF > /dev/null 2>&1; then
                log "NBD device ${DEV} already disconnected"
        else
                log "Disconnecting NBD device ${DEV}"
                ${QEMU_NBD_BINARY} --disconnect "${DEV}" 2>> "${LOG_FILE}" || log "Cannot disconnect ${DEV}" "ERROR"
                if [ "${VM_RUNNING}" == true ]; then
                        log "Restarting vm ${OPNSENSE_VM} since it was running"
                        ${VIRSH_BINARY} start "${OPNSENSE_VM}" 2>> "${LOG_FILE}" || log "Cannot start ${OPNSENSE_VM}" "ERROR"
                fi
        fi
        log "End of CleanUp"
}

TrapQuit() {
        local exitcode=0

        CleanUp

        if [ "${POST_INSTALL_SCRIPT_GOOD}" == true ]; then
                exitcode=0
        else
                exitcode=1
        fi
        exit $exitcode
}

DestroyVirshSnaphots() {
        vm="${1}"

        log "Remove all snapshots from ${vm}"
        for snapshot in $(virsh snapshot-list --name "${vm}"); do
                virsh snapshot-delete --snapshotname "$snapshot" "${vm}" 2>> "${LOG_FILE}"
                if [ $? -ne 0 ]; then
                        log "Cannot remove snapshot $snapshot from VM ${vm}, will try metadata-only" "ERROR"
                        virsh snapshot-delete --snapshotname "$snapshot" "${vm}" --metadata 2>> "${LOG_FILE}"
                        if [ $? -ne 0 ];  then
                                log "Cannot remove metadata snapshot $snapshot from VM ${vm}" "ERROR"
                        fi
                fi
        done
}

ExportVMxml() {
        vm="${1}"

        log "Exporting current VM ${vm} xml file"
        virsh dumpxml --security-info "$vm" > "${VM_XML}" || log_quit "Failed to dump XML for $vm in ${VM_XML}" "ERROR"
}

log "Starting EL Goat script at $(date)"
[ -z "${BASH_VERSION}" ] && log_quit "This script must be run with bash" "ERROR"

# Shutdown current opnsense VM if running
if [ "$(${VIRSH_BINARY} domstate "${OPNSENSE_VM}")" == "running" ]; then
        log "Machine ${OPNSENSE_VM} running. Shut it down for modifications"
        ${VIRSH_BINARY} shutdown "${OPNSENSE_VM}" 2>> "${LOG_FILE}" || log "Cannot shutdown ${OPNSENSE_VM}" "ERROR"
        timer=0
        while [ "$(${VIRSH_BINARY} domstate "${OPNSENSE_VM}")" == "running" ]; do
                echo -n .
                sleep 1
                timer=$((timer+1))
                if [ "${timer}" -gt ${VM_SHUTDOWN_TIMEOUT} ]; then
                        log "Forcing stop of ${OPNSENSE_VM} after ${timer} seconds"
                        ${VIRSH_BINARY} destroy "${OPNSENSE_VM}" 2>> "${LOG_FILE}" || log_quit "Cannot destroy ${OPNSENSE_VM}" "ERROR"
                fi
                if [ $((timer % 30)) -eq 0 ]; then
                        log "Machine ${OPNSENSE_VM} still running after ${timer} seconds, waiting for shutdown"
                fi
        done
else
        VM_RUNNING=false
        log "Machine ${OPNSENSE_VM} not running, proceeding"
fi

# First TrapQuit declaration before knowing if we run as daemon or not
trap TrapQuit TERM EXIT HUP QUIT

# Load qemu-nbd module
if lsmod | grep "^nbd" > /dev/null 2>&1; then
        log "nbd kernel module is loaded"
else
        log "Trying to load nbd kernel module"
        modprobe nbd 2>> "${LOG_FILE}" || log "Cannot load module nbd" "ERROR"
fi

# Mount opnsense disk only if /dev/nbd0 is empty
if cmp -n 512 /dev/nbd0 /dev/zero 2>&1 | grep EOF > /dev/null 2>&1; then
        log "Attaching NDB device ${DEV}"
        ${QEMU_NBD_BINARY} --connect "${DEV}" "${DISK_IMAGE}" 2>> "${LOG_FILE}" || log_quit "Cannot mount disk_image ${DISK_IMAGE}" "ERROR"
        # Arbitrary sleep time
        sleep ${SLEEP_TIME}
else
        log "NBD device ${DEV} is already attached"
fi

if zpool list ${ZPOOL} > /dev/null 2>&1; then
        log "zpool ${ZPOOL} is already imported"
else
        # Import zpool
        log "Import zpool ${ZPOOL}"
        ${ZPOOL_BINARY} import -N ${ZPOOL} 2>> "${LOG_FILE}" || log_quit "Cannot import ${ZPOOL}" "ERROR"
fi

# Create mountpoint if not existing
if [ ! -d "${MOUNT_POINT}" ]; then
        log "Creating local mountpoint ${MOUNT_POINT}"
        mkdir -p "${MOUNT_POINT}"  2>> "${LOG_FILE}" || log_quit "Cannot create local mountpoint ${MOUNT_POINT}" "ERROR"
fi

log "Changing zpool mountpoint to ${MOUNT_POINT}"
${ZFS_BINARY} set mountpoint=${MOUNT_POINT} ${ZROOT} 2>> "${LOG_FILE}" || log_quit "Cannot change mountpoint ${MOUNT_POINT} in ${ZROOT}" "ERROR"

if mount | grep ${ZROOT} > /dev/null 2>&1; then
        log "zpool ${ZROOT} is already mounted"
else
        log "Mounting zpool ${ZROOT}"
        ${ZFS_BINARY} mount ${ZROOT} 2>> "${LOG_FILE}" || log_quit "Cannot mount ${ZROOT}" "ERROR"
fi

# Actual interace name replacing
index=0
for interface in "${INTERFACES_TO_REPLACE[@]}"; do
        log "Replacing ${interface} with ${INTERFACES_REPLACEMENT[$index]}" "INFO"
        sed -i 's#<members>'${interface}'</members>#<members>'${INTERFACES_REPLACEMENT[$index]}'</members>#g' "${MOUNT_POINT}${CONF_FILE}" 2>> "${LOG_FILE}"
        if [ $? != 0 ]; then
                log_quit "Could not modify members of our mighty lagg0" "ERROR"
        else
                log "Yihaa. lagg0 now uses igb interfaces"
        fi
        index=$((index+1))
done

# Optional steps, change some config in the current VM
log "Changing machine type"
# Optional changes to machine (here, we update from Almalinux 9 to AlmaLinux 10 compat)
sed -i "s#<type arch='x86_64' machine='pc-i440fx-rhel7.6.0'>hvm</type>#<type arch='x86_64' machine='pc-i440fx-rhel10.0.0'>hvm</type>#g" "${VM_XML}" 2>> "${LOG_FILE}" || log_quit "Cannot update VM type in ${VM_XML}" "ERROR"

# Remove all snapshots from VM before being able to unregister it
DestroyVirshSnaphots "${OPNSENSE_VM}"
ExportVMxml "${OPNSENSE_VM}"

if ! virsh list --all --name | grep "${OPNSENSE_VM}" > /dev/null 2>&1; then
        log "Machine ${OPNSENSE_VM} is not defined"
else
        log "Undefining ${OPNSENSE_VM}"
        ${VIRSH_BINARY} undefine "${OPNSENSE_VM}" 2>> "${LOG_FILE}" || log "Cannot undefine ${OPNSENSE_VM}" "ERROR"
fi

log "Defining ${OPNSENSE_VM}"
${VIRSH_BINARY} define "${VM_XML}" 2>> "${LOG_FILE}" || log_quit "Cannot define VM from ${VM_XML}" "ERROR"

# Once we're done, Trapquit is automatically launched which will launch CleanUp()
