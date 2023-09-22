#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


set -e

function output_variables {
    echo "Machine: $machine"
    echo "Repo: $repo"
    echo "Branch: $branch"
    echo "Workload: $workload"
    echo "Build Flags: $build_flags"
    echo "BOLT: $bolt"
    echo "Use Docker Cache: $cache"
    echo "------------------------------------------"
}

help() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  -w workload: specify the workload name. [ -w webtooling / ghost_http / ghost_https ]"
  echo "  -b branch: specify the branch name. [-b v18.14.2 / ...]"
  echo "  -n build_flags: specify the build flags of node/anode repo. [-n \"--v8-enable-hugepage\"]"
  echo "  -o bolt: apply bolt [-o]"
  echo "  -c clear all docker cache [-c]"
  echo "  -h display this help message"
}

source ./config.sh
echo "Loaded configration from config.sh."
echo "Please make sure there is no problem with the config.sh parameters. "
echo "------------------------------------------"

# repo
while getopts "w:b:n:o c C:P h" opt
do
  case $opt in
    w) workload=$OPTARG ;;
    b) branch=$OPTARG ;;
    n) build_flags=$OPTARG ;;
    o) bolt="true";;
    c) cache="false" ;;
    C) clear=$OPTARG ;;
    P) use_proxy="true" ;;
    h) help; exit 0 ;;
    ?) echo "Invalid option."; exit 1 ;;
  esac
done

echo "Loaded input parameters..."
output_variables

# Check if cache is set to true
no_cache=$( [ "$cache" = "true" ] && echo "false" || echo "true" )

if [ ! -z "$clear" ] && [ "$cache" = "false" ]; then
  echo "Erorr! Option[-C] and Option[-c] cannot be use together."
  exit 1
elif [ ! -z "$clear" ]; then
  no_cache=$clear
fi

nodeio_case="none"
if [ $workload = "nodeio" ]; then
  nodeio_case=(socket http https grpc)
  echo "Please input the case of nodeio you need to build: [socket/http/https/http2/grpc]"
  read nodeio_case
fi

cd ../tools
script="./build_workload.py"

if [ $use_proxy = "true" ]; then
  hproxy=$http_proxy
  hsproxy=$https_proxy
  echo "use http_proxy: $http_proxy"
  echo "use https_proxy: $https_proxy"
else
  hproxy=""
  hsproxy=""
fi

python3 $script \
-w $workload \
-r $repo \
-b $branch \
-n="$build_flags" \
--bolt $bolt \
-d "No" \
-c $no_cache \
--case $nodeio_case \
--http-proxy="$hproxy" \
--https-proxy="$hsproxy"
