#!/usr/bin/env bash

# Machine create script 2025040401

# TODO: Since libvirt 9.1.0, q35 vm include itco watchdog by default, se we should remove i6300esb by default as per https://libvirt.org/formatdomain.html#watchdog-devices

# OS (get with osinfo-query os)
OS_VARIANT=rhel9.5
ISO=/data/public_vm/ISO/AlmaLinux-9.5-x86_64-dvd.iso
ISO=/opt/AlmaLinux-9.5-x86_64-dvd.iso
#OS_VARIANT=debian12
#ISO=/data/public_vm/ISO/debian-12.9.0-amd64-DVD-1.iso
#OS_VARIANT=win2k22
#ISO=/data/public_vm/ISO/fr-fr_windows_server_2022_x64_dvd_9f7d1adb.iso
#OS_VARIANT=opensuse15.5
#ISO=/data/public_vm/ISO/grommunio.x86_64-latest.install.iso
#OS_VARIANT=debian12
#ISO=/data/public_vm/ISO/proxmox-mail-gateway_8.1-1.iso
#OS_VARIANT=freebsd14.0
#ISO=/opt/OPNsense-25.1-dvd-amd64.iso

# BOOT_TYPE = cdrom when no kernel can be directly loaded (used for appliances and windows)
#BOOT_TYPE=cdrom

TENANT=npf
VM=___vmname___.${TENANT}.local
DISKSIZE=100G
DISKPATH=/data/public/${TENANT}
#DISKPATH=/var/lib/libvirt/images
DISKFULLPATH="${DISKPATH}/${VM}-disk0.qcow2"
VCPUS=4
RAM=4096

W
IO_MODE=,io="native"
# For IO intensive machines, the followng will improve latency at the cost of slighty lower IOPS
# io=threads still reduces performances overall, so io=native,iothread=x is good
#IO_MODE=,io="native,driver.iothread=1,driver.queues=${VCPUS} --iothreads 1"

# Paramètres VM
PRODUCT=vm_elconf
VERSION=5.0
MANUFACTURER=NetPerfect
VENDOR=netperfect_vm

#IP=
#NETMASK=
#GATEWAY=
#NAMESERVER=

NPF_TARGET=generic
#NPF_USER_NAME=user
#NPF_USER_PASSWORD=
#NPF_ROOT_PASSWORD=

# Host names can only contain the characters 'a-z', 'A-Z', '0-9', '-', or '.', cannot start or end with '-'
NPF_HOSTNAME="${VM}"
if [ "${IP}" != "" ] && [ "${NETMASK}" != "" ]; then
       # This is for pre script to pick up
       NPF_NETWORK="${IP}:${NETMASK}:${GATEWAY}:${NAMESERVER}"
       # This is for anaconda installer to pick up
       IP="ip=${IP}::${GATEWAY}:${NETMASK}:${VM}:none nameserver=${NAMESERVER}"
       #IP="ip=192.168.151.11::192.168.151.254:255.255.255.0:${VM}:none nameserver=192.168.151.254"
fi

#VIDEO="--graphics none"
VIDEO="--video virtio --graphics vnc,listen=127.0.0.1,keymap=fr"

#BRIDGE="--network bridge=br_dmzint"
#BRIDGE="--network bridge=br_${TENANT}"
#BRIDGE="--network bridge=br_cloudstack"
BRIDGE="--network bridge=br_net0"
#PCI_PASSTHROUGH="--host-device pci_0000_03_00_0 --network none"
#BRIDGE="--network bridge=br_dmzext"

INST="inst.text inst.lang=en_US inst.keymap=fr"
KICKSTART=/root/ks.rhel9.cfg

## Prepare commands
if [ ${OS_VARIANT:0:3} == "win" ] || [ "$BOOT_TYPE" == "cdrom" ]; then
        BOOT_ARGS="--cdrom ${ISO}"
        extra_args=""
else
        BOOT_ARGS="--location ${ISO}"
        extra_args="console=tty0 console=ttyS0,115200n8 ${INST} ${IP}"
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
        vm_cmd='virt-install --name '${VM}' --ram '${RAM}' --vcpus '${VCPUS}' --cpu host --os-variant '${OS_VARIANT}' --disk path='${DISKFULLPATH}',bus=virtio,cache=none'${IO_MODE}' --channel unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0 --watchdog i6300esb,action=reset --sound none --boot hd --autostart --sysinfo smbios,bios.vendor='${VENDOR}',system.manufacturer='${MANUFACTURER}',system.version='${VERSION}',system.product='${PRODUCT}' '${BOOT_ARGS}' '${VIDEO}' '${BRIDGE}' --autoconsole text'
else
        vm_cmd='virt-install --name '${VM}' --ram '${RAM}' --vcpus '${VCPUS}' --cpu host --os-variant '${OS_VARIANT}' --disk path='${DISKFULLPATH}',bus=virtio,cache=none'${IO_MODE}' --channel unix,mode=bind,target_type=virtio,name=org.qemu.guest_agent.0 --watchdog i6300esb,action=reset --sound none --boot hd --autostart --sysinfo smbios,bios.vendor='${VENDOR}',system.manufacturer='${MANUFACTURER}',system.version='${VERSION}',system.product='${PRODUCT}' '${BOOT_ARGS}' --extra-args "'${extra_args}'" '${KICKSTART_INJECT}' '${VIDEO}' '${BRIDGE}' --autoconsole text'
fi
echo $vm_cmd
eval "$vm_cmd"
