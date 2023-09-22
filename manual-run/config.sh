#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


machine="SPR"
use_proxy="false"
repo="https://github.com/nodejs/node.git"
branch="v18.14.2"

# build flags
workload="webtooling"
build_flags="--openssl-no-asm --experimental-enable-pointer-compression --enable-pgo-use --v8-enable-hugepage --v8-enable-short-builtin-calls"
#build_flags=""
bolt="false"
cache="true"

# run Flags
run_flags=""
cpuset="false"
nums="1"

# perf args
perf_args="--delay 5 --call-graph=fp --clockid=mono --output=perf.data -g"
