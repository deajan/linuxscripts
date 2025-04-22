#!/usr/bin/env bash

vms=$(virsh list --all --name)
for vm in ${vms[@]}; do
        echo "VM Name: $vm"
        virsh snapshot-list --tree $vm
done
