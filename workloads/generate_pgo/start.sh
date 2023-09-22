#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


# Collect pgo data from webtooling.
cd web-tooling-benchmark
~/work/node/out/Release/node --max-semi-space-size=128 dist/cli.js
mv ~/work/node/pgodata/ ~/pgodata1

# Collect pgo data from ghost-https.
cd /
sudo ./usr/local/bin/entrypoint.sh

# start server
cd ~/Ghost
NODE_ENV=production ~/work/node/out/Release/node --max-semi-space-size=256 current/index.js &
pid=$!

# start ab
sleep 10
ab -c 50 -n 20000 http://localhost:2368/
sleep 5

kill -INT $pid
sleep 10
mv ~/work/node/pgodata/ ~/pgodata2

# Merge two pgo-data into one.
cd ~
gcov-tool-10 merge pgodata1/ pgodata2/ -o ~/pgodata
tar zcvf pgofile.tar.gz pgodata