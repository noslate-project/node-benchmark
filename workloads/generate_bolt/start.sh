#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


function perf_ghost() {
    export NODE_ENV=production
    perf record -e cycles:u -j any,u -o perf.data -- /home/ubuntu/work/node/out/Release/node --max-semi-space-size=256 current/index.js &
}


sudo sh -c "echo -1 > /proc/sys/kernel/perf_event_paranoid"
sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"


cd ~/work/node
make -j$((`nproc`-1))

# collect web-tooling
cd ~/web-tooling-benchmark
perf record -e cycles:u -j any,u -o perf.data -- /home/ubuntu/work/node/out/Release/node --max-semi-space-size=128 dist/cli.js
sleep 10

# collect ghost
sudo service mysql start
sudo nginx -c /home/ubuntu/nginx/nginx.conf

cd ~/Ghost
perf_ghost
# export NODE_ENV=production && \
# perf record -e cycles:u -j any,u -o perf.data -- /home/ubuntu/work/node/out/Release/node --max-semi-space-size=256 current/index.js &

sleep 10

ab -c 50 -n 20000 http://localhost:2368/
sleep 5
pid_perf=$(pidof perf)
kill -INT $pid_perf
ls
sleep 60

# Generate files
cp ~/web-tooling-benchmark/perf.data ~/perf1.data
cp ~/Ghost/perf.data ~/perf2.data
cd ~
work/build/bin/perf2bolt -p perf1.data -o perf1.fdata -skip-funcs=Builtins_.* /home/ubuntu/work/node/out/Release/node
echo "perf1.fdata completed!"

work/build/bin/perf2bolt -p perf2.data -o perf2.fdata -skip-funcs=Builtins_.* /home/ubuntu/work/node/out/Release/node
echo "perf2.fdata completed!"

work/build/bin/merge-fdata perf1.fdata perf2.fdata > perf.fdata
rm -rf perf.fdata.gz
gzip -k perf.fdata