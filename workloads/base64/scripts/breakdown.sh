#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

perf_args=${1:-"--call-graph=fp --clockid=mono --output=perf.data -g"}

perf record $perf_args \
    node --perf-prof --no-write-protect-code-memory --interpreted-frames-native-stack \
    /home/ubuntu/work/node/benchmark/buffers/buffer-base64-encode.js

wait

sleep 5
echo "Start profiling..."
perf inject -j -i perf.data -o perf.data.jitted
sleep 2
perf script -f --input=perf.data.jitted | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl --color=js > output.svg

perf report --header --children -U -g callee,folded,0.5 --sort=dso,symbol > perf.profile
perf report --no-children > perf.report

python2 perf_module_breakdown.py perf.data.jitted

# perf.data.tar.bz2
version="linux-5.15"
perf_path="$version/tools/perf"

wget https://mirrors.edge.kernel.org/pub/linux/kernel/v5.x/$version.tar.xz

tar xvf $version.tar.xz
cd $perf_path

export CC=gcc

apt install -y flex
make ARCH=x86_64

cd /home

./$perf_path/perf-archive perf.data
tar xvf perf.data.tar.bz2 -C ~/.debug
