#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


RESULTS_DIR="workspace-`date +%F_%H-%M-%S`"; # Where to store the results
OUTPUT_FILE_PREFIX="example-run";            # Prefix to use for output files. Must not contain periods.
ITERATIONS=1;                                # How many iterations to run
TIMEOUT=10;			             # Timeout between warmup and measurement. '' to wait until the user presses Enter.
THREADS=1; 			             # How many processes to run(ex. `nproc`); multiple threads can be specified, comma separated
PARA1="$1";
NODE_VERSION="${PARA1:-14.17.0}";            # Node binary version string
PARA2="$2";
PROTOCOL="${PARA2:-http}";                   # Testing protocol: http or https
NODE_RUN_FLAGS="$3";                         # Runtime flags for node.js ('--flag1 --flag2')

../ghost-benchmark-scripts/launch-many-processes-rps-collect /home/ghost/ghost-benchmark-scripts/ /home/ghost/Ghost/${RESULTS_DIR} "node ${NODE_RUN_FLAGS} " ${OUTPUT_FILE_PREFIX} ${ITERATIONS} /home/ghost/Ghost/ 4.4.0 ${TIMEOUT} ${THREADS} ${PROTOCOL} 2>&1 | tee runoutput;tar cvf ablog.tar ${RESULTS_DIR};cd ${RESULTS_DIR};/home/ghost/ghost-benchmark-scripts/summarize-many-processes-rps-data  . >../output