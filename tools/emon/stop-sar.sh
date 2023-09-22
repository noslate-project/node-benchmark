#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

sarpid=$(pidof sar)
kill -2 $sarpid

# Wait until the process actually finishes
# We have to do this because we cannot call wait on a non-child process
while true ; do
    kill -0 $sarpid > /dev/null 2>&1
    if [ $? -ne 0 ]; then break ;fi
    sleep 0.5
done
