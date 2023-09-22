#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


set -e

function output_variables {
    echo "------------------------------------------"
    echo "Machine: $machine"
    echo "Repo: $repo"
    echo "Branch: $branch"
    echo "Workload: $workload"
    echo "Build Flags: $build_flags"
    echo "Run Flags : $run_flags"
    echo "BOLT: $bolt"
    echo "Cpu Set : $cpuset"
    echo "Use Docker Cache: $cache"
    echo "------------------------------------------"
}

function help {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -w workload: specify the workload name. [-w webtooling]"
  echo "  -b branch: specify the branch name. [-b v18.14.2]"
  echo "  -n build_flags: specify the build flags of node/anode repo. [-n \"--v8-enable-hugepage\"]"
  echo "  -o bolt: apply bolt [-o]"
  echo "  -i nums: running instance nums. [-i 224]"
  echo "  -r run_flasgs: specify the run flags of node/anode. [-r \"--max-semi-space-size=256\"]"
  echo "  -s cpuset: docker --cpuset-cpus=x,x. "
  echo "  -c clear docker cache [-c]"
  echo "  -h: display this help message [-h]"
}

source ./config.sh
echo "Loaded configration from config.sh."
echo "Please make sure there is no problem with the config.sh parameters. "
echo "------------------------------------------"

while getopts "w:b:n:o i:r:s c h" opt
do
  case $opt in
    w) workload=$OPTARG ;;
    b) branch=$OPTARG ;;
    n) build_flags=$OPTARG ;;
    o) bolt="true" ;;
    i) nums=$OPTARG ;;
    r) run_flags=$OPTARG ;;
    s) cpuset="true" ;;
    c) cache="false" ;;
    h) help; exit 0 ;;
    ?) echo "Invalid option: -$OPTARG" ;;
  esac
done

echo "Loaded input parameters..."
output_variables

cd ../tools
script="./run_workload.py"

if [ "$workload" = "ssr_calcom" -a "$cpuset" = "true" ]; then
  echo "Error! Cpuset is always true in SSR workload. No need run ssr with '-s'."
  exit 1
fi

if [ $workload = "nodeio" ]; then
 echo "Please input the case of nodeio you need to build:"
 read case_type
 declare -A params 
 echo "client_num"
 read params["client_num"] 
 echo "message_num"
 read params["message_num"]
 echo "conn_num"
 read params["conn_num"] 
 echo "message_size"
 read params["message_size"]
 echo "stream_num"
 read params["stream_num"]
 key_string=$(printf "%s " "${!params[@]}")
 value_string=$(printf "%s " "${params[@]}")
fi

python3 $script \
-w $workload \
-r $repo \
-b $branch \
-n="$build_flags" \
--bolt $bolt \
-l="$run_flags" \
--cpuset $cpuset \
-i $nums \
-d "No" \
--case="$case_type" \
--nodeio-key="$key_string" \
--nodeio-value="$value_string"