#!/bin/bash

printf '%-20s %-4s %-8s\n' "Vm Name" "CPU(s)" "RAM (MiB)"

mapfile -t vm_array < <( virsh list --all --name )

while read -r vm
do
        if [ ! -z "$vm" ]; then
                MEM_USED=$(($(virsh dominfo $vm | grep "Max memory" | cut -f 7 -d " ") / 1024))
                CPU_USED=$(virsh dominfo $vm | grep "CPU(s)" | cut -f 10 -d " ")
                printf "%-40s %4s | %8s\n" "$vm" "$CPU_USED"  "$MEM_USED"
                MEM_SUM=$((MEM_SUM + MEM_USED))
                CPU_SUM=$((CPU_SUM + CPU_USED))
        fi
done < <( printf '%s\n' "${vm_array[@]}")

printf -- '-%.0s' {1..36}
printf '\n%-40s %4s | %8s\n' "Totals:" "$CPU_SUM" "$MEM_SUM"
