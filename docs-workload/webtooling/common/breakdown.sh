#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

set -e

run_flags=$1
perf_args=${2:-"--delay 5 --call-graph=fp --clockid=mono --output=perf.data -g"}

# Sometimes avoid RAM not enough for profiling
pre_process=${3:-"true"}

# Start Perf
cd /home/ubuntu/web-tooling-benchmark
perf record $perf_args \
     /home/ubuntu/work/node/out/Release/node --perf-prof --no-write-protect-code-memory --interpreted-frames-native-stack $run_flags \
     dist/cli.js

wait

sleep 5
echo "Start profiling..."

echo "Generating perf.data.jitted..."
perf inject -j -i perf.data -o perf.data.jitted || echo "Failed"
sleep 2

echo "Generating output.svg..."
perf script -f --input=perf.data.jitted | ../FlameGraph/stackcollapse-perf.pl | ../FlameGraph/flamegraph.pl --color=js > output.svg || echo "Failed"

echo "Generating perf.profile..."
perf report --header --children -U -g callee,folded,0.5 --sort=dso,symbol > perf.profile || echo "Failed"

echo "Generating perf.report..."
perf report --no-children > perf.report || echo "Failed"

echo "Generating result.txt..."
python2 perf_module_breakdown.py perf.data.jitted || echo "Failed"

# generate perf.data.tar.bz2
echo "Generating perf.data.tar.bz2..."
./perf-archive perf.data || echo "Failed"
tar xvf perf.data.tar.bz2 -C ~/.debug || echo "tar Failed"

echo "All completed!"