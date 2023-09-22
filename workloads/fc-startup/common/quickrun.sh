#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


req_num=$1
req_interval=$2
run_flags=$3
total=0

for i in `seq 1 $1`;
do
        start=$(date +%s%3N)
        node $run_flags index.js
        end=$(date +%s%3N)
        total=$((total+end-start))
        if [ $req_interval != 0 ]; then
                sleep $req_interval
        fi
done 

average=$((total/req_num))

echo baseline: $req_num requests in $total ms, average is $average ms.
