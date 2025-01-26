#!/bin/bash

# params
#   - device name (e.g. mlx5_0)
#   - number of virtual functions (e.g. 10)
configure_dev () {
        local num_of_vfs="$2"
        local devid=$(echo $1 | cut -d_ -f2)
        local max_id="0"
        local num_vfs_path="/sys/class/infiniband/$1/device/mlx5_num_vfs"
        if [[ "$(cat $num_vfs_path)" -lt "$num_of_vfs" ]]; then
                echo $num_of_vfs > /sys/class/infiniband/$1/device/mlx5_num_vfs
        fi
        let "max_id=$num_of_vfs-1"
        for vf in $(seq 0 $max_id); do
                echo ' ' ' ' Configuring virtual function $vf
                # enable the virtual function
                echo Follow > /sys/class/infiniband/$1/device/sriov/$vf/policy

                # assign GUID to virtual card and port
                let "first_part=$vf/100"
                let "second_part=$vf-$first_part*100"
                local ip_last_seg=$(hostname -i | cut -d. -f4)
                let "ip_last_seg_first=$ip_last_seg/100"
                let "ip_last_seg_second=$ip_last_seg-$ip_last_seg_first*100"
                local guid_prefix="$(printf "%02d" $devid):22:33:$(printf "%02d" $first_part):$(printf "%02d" $second_part):$(printf "%02d" $ip_last_seg_first):$(printf "%02d" $ip_last_seg_second)"
                echo "$guid_prefix:90" > /sys/class/infiniband/$1/device/sriov/$vf/node
                echo "$guid_prefix:91" > /sys/class/infiniband/$1/device/sriov/$vf/port

                # reload driver to make the change effective
                pcie_addr="$(readlink -f /sys/class/infiniband/$1/device/virtfn${vf} | awk -F/ '{print $NF}')"
                echo $pcie_addr > /sys/bus/pci/drivers/mlx5_core/unbind
                echo $pcie_addr > /sys/bus/pci/drivers/mlx5_core/bind
        done
}

# if specific devices are provided, only those will be configured
# otherwise, all devices supporting SR-IOV will be configured
if [[ "$#" -eq "0" ]]; then
        echo Configuring SR-IOV for all supported devices
        for dev in $(ls /sys/class/infiniband); do
                totalvfs_path="/sys/class/infiniband/$dev/device/sriov_totalvfs"
                if [[ -e "$totalvfs_path" && "$(cat $totalvfs_path)" -gt "0" ]]; then
                        echo ' ' Configuring for $dev $(cat $totalvfs_path)
                        #configure_dev $dev $(cat $totalvfs_path)
                fi
        done
elif ! (( $# % 2 )); then
        echo Configuring SR-IOV for specified devices
        while (( "$#" )); do
                dev=$1
                num_of_vfs=$2
                echo ' ' Configuring for $dev
                configure_dev $dev $num_of_vfs
                shift 2
        done
else
        echo Please use the script in the following two ways:
        echo ' ' ./mlnx.sh
        echo ' ' ./mlnx.sh mlx5_0 10 mlx5_1 25
fi
