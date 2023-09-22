#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


LLVM_VERSION=$2
LLVM_URL=$3
file=$4

if [ $1 = "true" ]; then
    # clone llvm repo
    cd /home/ubuntu/work
    git clone --depth 1 --branch ${LLVM_VERSION} ${LLVM_URL}
    
    # build llvm
    mkdir build && cd build
    cmake -G Ninja /home/ubuntu/work/llvm-project/llvm \
    -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_ENABLE_PROJECTS="bolt"

    ninja bolt

    # copy
    cp ../pgo-bolt/$file ./perf.fdata.gz
    gzip -d perf.fdata.gz

    ./bin/llvm-bolt \
    ../node/node_bin/bin/node \
    -o node.bolt \
    -data=perf.fdata \
    -reorder-blocks=cache+ \
    -reorder-functions=hfsort+ \
    -split-functions=2 \
    -split-all-cold \
    -split-eh \
    -dyno-stats \
    -skip-funcs=Builtins_.*

    # rename with node.bolt
    cp /home/ubuntu/work/build/node.bolt /usr/local/bin/node

    # delete unused files
    rm -rf /home/ubuntu/work/build
    rm -rf /home/ubuntu/work/llvm-project

    echo "BOLT-patch files is OK."
else
    echo "No BOLT-patch."
fi