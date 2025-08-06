#!/usr/bin/env bash

# Machine create script 2025070401

# Use standard or UEFI boot
BOOT=hd
# Boot a kernel or just load a standard cdrom bootfile
BOOT_TYPE=kernel

# OS (get with osinfo-query os)

# Example for RHEL 10
OS_VARIANT=rhel10.0
ISO=/public_vm3/iso/AlmaLinux-10.0-x86_64-dvd.iso
KICKSTART=/root/ks.el9-10.cfg

# RHEL 9
#OS_VARIANT=rhel9.6
#ISO=/opt/AlmaLinux-9.6-x86_64-dvd.iso
#KICKSTART=/root/ks.el9-10.cfg

# Debian 12
#OS_VARIANT=debian12
#ISO=/data/public_vm/ISO/debian-12.9.0-amd64-DVD-1.iso

# Windows Server 2022
#OS_VARIANT=win2k22
#OS_VARIANT=win11
#ISO=/data/public_vm/ISO/fr-fr_windows_server_2022_x64_dvd_9f7d1adb.iso
#BOOT=uefi
#BOOT_TYPE=cdrom
#VIRTIO_ISO=/data/public_vm/ISO/virtio-win-0.1.271.iso
#VIDEO="--video virtio --graphics vnc,listen=127.0.0.1,keymap=fr"
#TPM="--tpm emulator"

# Grommunio based on OpenSUSE 15.6 (needs graphical interface for console menu)
#OS_VARIANT=opensuse15.5
#ISO=/data/public_vm/ISO/grommunio.x86_64-latest.install.iso
#BOOT_TYPE=cdrom
#VIDEO="--video virtio --graphics vnc,listen=127.0.0.1,keymap=fr"

# Proxmox
#OS_VARIANT=debian12
#ISO=/data/public_vm/ISO/proxmox-mail-gateway_8.1-1.iso
#BOOT_TYPE=cdrom
#VIDEO="--video virtio --graphics vnc,listen=127.0.0.1,keymap=fr"

# OPNSense
#OS_VARIANT=freebsd14.0
#ISO=/opt/OPNsense-25.1-dvd-amd64.iso
#BOOT=hd


TENANT=tenant
VM=haproxy01p.${TENANT}.local
DISKSIZE=30G
DISKPATH=/public_vm3/${TENANT}
#DISKPATH=/var/lib/libvirt/images
DISKFULLPATH="${DISKPATH}/${VM}-disk0.qcow2"
VCPUS=1
RAM=2048
BRIDGE_NAME=br_${TENANT}
#BRIDGE_NAME=
BRIDGE_MTU=1330

# IO MODE io_uring is fastest on io intesive VMs
# IO MODE native with threads is fast
# IO MODE native has good latency
IO_MODE=,io="native"
# For IO intensive machines, the followng will improve latency at the cost of slighty lower IOPS
# io=threads still reduces performances overall, so io=native,iothread=x is good
#IO_MODE=,io="native,driver.iothread=1,driver.queues=${VCPUS} --iothreads 1"
#IO_MODE=,io="io_uring,driver.queues=${VCPUS} --iothreads 4"

# Paramètres VM
PRODUCT=vm_elconf
VERSION=5.0
MANUFACTURER=NetPerfect
VENDOR=netperfect_vm

#IP=192.168.21.1
#NETMASK=255.255.255.0
#GATEWAY=192.168.21.254
#NAMESERVER=192.168.21.254

NPF_TARGET=generic
#NPF_USER_NAME=user
#NPF_USER_PASSWORD=password
#NPF_ROOT_PASSWORD=rootpassword

# Host names can only contain the characters 'a-z', 'A-Z', '0-9', '-', or '.', cannot start or end with '-'
NPF_HOSTNAME="${VM}"
if [ "${IP}" != "" ] && [ "${NETMASK}" != "" ]; then
       # This is for pre script to pick up
       NPF_NETWORK="${IP}:${NETMASK}:${GATEWAY}:${NAMESERVER}"
       # This is for anaconda installer to pick up
       IP="ip=${IP}::${GATEWAY}:${NETMASK}:${VM}:none nameserver=${NAMESERVER}"
       #IP="ip=192.168.151.11::192.168.151.254:255.255.255.0:${VM}:none nameserver=192.168.151.254"
fi

# If no specific video is asked, consider we're using VNC
if [ -z "${VIDEO}" ]; then
        VIDEO="--graphics none"
fi

BRIDGE="--network bridge=${BRIDGE_NAME},mtu.size=${BRIDGE_MTU}"
#PCI_PASSTHROUGH="--host-device pci_0000_03_00_0 --network none"

# 440fx machines as well as libvirt < 9.1.0 still need manual watchdog
#WATCHDOG="--watchdog i6300esb,action=reset"

INST="inst.text inst.lang=en_US inst.keymap=fr"

## Prepare commands
if [ "$BOOT_TYPE" == "cdrom" ]; then
        BOOT_ARGS="--cdrom ${ISO}"
        if [ ${OS_VARIANT:0:3} != "win" ]; then
                extra_args="console=tty0 console=ttyS0,115200n8"
        fi
else
        BOOT_ARGS="--location ${ISO}"
        extra_args="console=tty0 console=ttyS0,115200n8 ${INST} ${IP}"
fi

# Add virtio ISO for windows
if [ ${OS_VARIANT:0:3} == "win" ]; then
        BOOT_ARGS="${BOOT_ARGS} --disk device=cdrom,path=${VIRTIO_ISO},bus=sata"
fi

if [ "${KICKSTART}" != "" ]; then
        extra_args="${extra_args} inst.ks=file:/$(basename ${KICKSTART}) inst.nosave=all_ks"
        KICKSTART_INJECT="--initrd-inject ${KICKSTART}"
fi

[ -n "${NPF_TARGET}" ] && extra_args="${extra_args} NPF_TARGET=${NPF_TARGET}"
[ -n "${NPF_USER_NAME}" ] && extra_args="${extra_args} NPF_USER_NAME=${NPF_USER_NAME}"
[ -n "${NPF_USER_PASSWORD}" ] && extra_args="${extra_args} NPF_USER_PASSWORD=${NPF_USER_PASSW0RD}"
[ -n "${NPF_ROOT_PASSWORD}" ] && extra_args="${extra_args} NPF_ROOT_PASSWORD=${NPF_ROOT_PASSWORD}"
[ -n "${NPF_HOSTNAME}" ] && extra_args="${extra_args} NPF_HOSTNAME=${NPF_HOSTNAME}"
[ -n "${NPF_NETWORK}" ] && extra_args="${extra_args} NPF_NETWORK=${NPF_NETWORK}"

## Create tenant dir if not exit
[ ! -d "$DISKPATH" ] && mkdir "$DISKPATH" && chown qemu:qemu "$DISKPATH"

# -o cluster_size=64k 64k is optimal for DB environment (and is default value), should match underlying storage cluster size (recordsize on zfs)
# -o lazy_refcounts: less IO (we mark image as dirty and it will be counted later). DO NOT ENABLE THIS since it may corrupt images and require a repair after a power loss
# -o refcount_bits= : 16 bits as default, 64 bits is default, the more the faster, but will need more memory cache to be configured
disk_cmd="qemu-img create -f qcow2 -o extended_l2=on -o preallocation=metadata -o cluster_size=64k "${DISKFULLPATH}" ${DISKSIZE}"
echo $disk_cmd
$disk_cmd
if [ $? != 0 ]; then
        echo "Disk creation failed"
        exit 1
fi

if [ ${OS_VARIANT:0:3} == "win" ] || [ "$BOOT_TYPE" == "cdrom" ]; then
        vm_cmd='virt-install --name '${VM}' --ram '${RAM}' --vcpus '${VCPUS}' --cpu host-model --os-variant '${OS_VARIANT}' --disk path='${DISKFULLPATH}',bus=virtio,cache=none'${IO_MODE}' --channel unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0  --sound none --boot '${BOOT}' --autostart --sysinfo smbios,bios.vendor='${VENDOR}',system.manufacturer='${MANUFACTURER}',system.version='${VERSION}',system.product='${PRODUCT}' '${BOOT_ARGS}' '${VIDEO}' '${BRIDGE}' '${TPM}' --autoconsole text'
else
        vm_cmd='virt-install --name '${VM}' --ram '${RAM}' --vcpus '${VCPUS}' --cpu host-model --os-variant '${OS_VARIANT}' --disk path='${DISKFULLPATH}',bus=virtio,cache=none'${IO_MODE}' --channel unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0  --sound none --boot '${BOOT}' --autostart --sysinfo smbios,bios.vendor='${VENDOR}',system.manufacturer='${MANUFACTURER}',system.version='${VERSION}',system.product='${PRODUCT}' '${BOOT_ARGS}' --extra-args "'${extra_args}'" '${KICKSTART_INJECT}' '${VIDEO}' '${BRIDGE}' '${TPM}' --autoconsole text'
fi
echo $vm_cmd
eval "$vm_cmd"
