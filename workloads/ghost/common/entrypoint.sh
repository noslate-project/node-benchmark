#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

: '
# Disable kernel ASLR (address space layout randomization)
echo -e "Disable kernel ASLR (address space layout randomization)"
sudo sysctl -w kernel.randomize_va_space=0
'

# Flush file system buffers
echo -e "Flushing file system buffers"
sudo sync

# Free pagecache, dentries and inodes
echo -e "Free pagecache, dentries and inodes"
sudo sh -c 'echo 3 >/proc/sys/vm/drop_caches'

# Free swap memory
echo -e "Free swap memory"
sudo swapoff -a
sudo swapon -a

: '
# Increase nf_conntrack hashtable size to 512000
echo -e "Increasing nf_conntrack hashtable size to 512000"
NF_CONNTRACK_MAX=/proc/sys/net/netfilter/nf_conntrack_max
if [ -e $NF_CONNTRACK_MAX ]; then
    echo 512000 | sudo tee  $NF_CONNTRACK_MAX
fi

# Set CPU scaling governor to max performance
echo -e "Setting CPU scaling governor to max performance"
if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
    for i in $(seq 0 $(($(nproc)-1))); do
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu"$i"/cpufreq/scaling_governor
    done
fi

# Set tcp socket reuse
echo -e "Setting TCP TIME WAIT"
echo 1 | sudo tee /proc/sys/net/ipv4/tcp_tw_reuse
'

# Setup the Database:
sudo bash /tmp/setup_db.sh
sudo service mysql start

#start nginx
echo -e "Starting nginx"
sudo nginx -c /home/ghost/nginx/nginx.conf

exec "$@"
