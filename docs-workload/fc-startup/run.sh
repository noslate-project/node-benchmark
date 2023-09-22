#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT
#
# Description of the test:
# This script is main script to run the multi-instance FaaS start up micro

#iterations, default to 5 to eliminate result variation
ITERATION_NUM=1

#number of instances: one workload instance is one container
INSTANCE_NUM=$1
IMAGE=$2
RUN_FLAGS=$3
BIND=${4:-nobind}
#number of instances: one workload instance is one container
REQ_NUM=30
REQ_INTERVAL=0.1

SLEEP=10
cdate=$(date +%Y-%m-%d-%H-%M-%S)
RESULT_DIR=results
mkdir -p "${RESULT_DIR}"

path=$(pwd | sed 's/tools/fc-startup/')
# SAVE_NAME="${IMAGE/:/-}"
SAVE_NAME=$IMAGE

cd $path
echo "The workload is: $path"

echo "./faas.sh $IMAGE $INSTANCE_NUM $REQ_NUM $REQ_INTERVAL $BIND noemon $RUN_FLAGS"
$path/faas.sh $IMAGE $INSTANCE_NUM $REQ_NUM $REQ_INTERVAL $BIND noemon $RUN_FLAGS
mv results/faas_score.json ${RESULT_DIR}/$SAVE_NAME\_${INSTANCE_NUM}ins_${REQ_NUM}req_$cdate.json
sleep $SLEEP
