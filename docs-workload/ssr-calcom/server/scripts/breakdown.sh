#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

set -e

run_flags=$1
perf_args=${2:-"--delay 10 --call-graph=fp --clockid=mono --output=perf.data -g"}

# Install Linux-Perf
# apt-get update && apt-get install -y python2 linux-tools-`uname -r`

# Replace node run flags
file="./apps/web/package.json"
sed -i "s/next start/node --perf-prof --no-write-protect-code-memory --interpreted-frames-native-stack $run_flags \/calcom\/cal.com\/node_modules\/next\/dist\/bin\/next start/g" $file

# Start perf record
cd /calcom/cal.com
./startdb.sh
sleep 5
perf record $perf_args yarn start &

sleep 25
echo "kill perf and node..."
pid_perf=$(pidof perf)
kill -INT $pid_perf

sleep 90
ls

echo "Start profiling..."
perf inject -j -i perf.data -o perf.data.jitted
sleep 2
perf script -f --input=perf.data.jitted | ../FlameGraph/stackcollapse-perf.pl | ../FlameGraph/flamegraph.pl --color=js > output.svg

perf report --header --children -U -g callee,folded,0.5 --sort=dso,symbol > perf.profile
perf report --no-children > perf.report

python2 perf_module_breakdown.py perf.data.jitted

# perf.data.tar.bz2
version="linux-5.15"
perf_path="/calcom/cal.com/$version/tools/perf"

wget https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/$version.tar.xz

tar xvf $version.tar.xz
cd $perf_path

export CC=gcc

apt install -y flex bison
make ARCH=x86_64

cd /calcom/cal.com

$perf_path/perf-archive perf.data
tar xvf perf.data.tar.bz2 -C ~/.debug
