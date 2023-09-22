#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


set -e

check_json() {
  result_path=$1
  ls $result_path/*.json > /dev/null 2>&1
  return $?
}

function compare_emon_version {
  emon_output=$(emon -v | grep "EMON Version")
  emon_version=$(echo "$emon_output" | cut -dV -f2 | tr -d ' ')

  sorted_versions=$(printf '%s\n%s\n' "$emon_version" "$1" | sort -V)
  if [ "$(echo "$sorted_versions" | head -n1)" = "$emon_version" ]; then
    echo "true"  # emon version < target version (11.41)
  else
    echo "false"
  fi
}

function output_variables {
    echo "------------------------------------------"
    echo "Machine: $machine"
    echo "Repo: $repo"
    echo "Branch: $branch"
    echo "Workload: $workload"
    echo "Build Flags: $build_flags"
    echo "Run Flags: $run_flags"
    echo "Perf Args: $perf_args"
    echo "BOLT: $bolt"
    echo "Cpu Set: $cpuset"
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
  echo "  -s cpuset: docker --cpuset-cpus=x,x. [-s]"
  echo "  -c  -c clear docker cache [-c]"
  echo "  -p perf collect [-p] "
  echo "  -e emon collect [-e] "
  echo "  -h: display this help message"
}

source ./config.sh
echo "Loaded configration from config.sh."
echo "Please make sure there is no problem with the config.sh parameters. "
echo "------------------------------------------"

while getopts "w:b:n:o i:r:s c p e h" opt
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
    p) perf="true" ;;   # perf
    e) emon="true" ;;   # emon
    h) help; exit 0 ;;
    ?) echo "Invalid option: -$OPTARG" ;;
  esac
done

echo "Loaded input parameters..."
output_variables

if [ "$workload" = "ssr_calcom" -a "$cpuset" = "true" ]; then
  echo "Error! Cpuset is always true in SSR workload. No need run ssr with '-s'."
  exit 1
fi

# module breakdown
if [ $perf ]; then
    echo "Parameters of perf: $perf_args"
    cd ../tools
    script="./breakdown_workload.py"

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
    -m $machine \
    -p="$perf_args"

    exit 0
fi


# collect emon data
if [ $emon ]; then
    # Judge the emon version, choose the correct emon-collect-method
    emon_flag=$(compare_emon_version "11.41")
    if [ "$emon_flag" = "true" ]; then
        emon_script="collect-emon-1139.sh"
        emon_process_script="process-emon-data-1139.sh"
    else
        emon_script="collect-emon-1141.sh"
        emon_process_script="process-emon-data-1141.sh"
    fi

    echo "Collect Emon Data."
    repo_path=$(cd .. ; pwd)
    workload_path=$repo_path/docs-workload

    # Run workload
    cd $repo_path/tools
    script1="./run_workload.py"; script2="./get_image_name.py"
    python3 $script1 -w $workload -r $repo -b $branch -n="$build_flags" --bolt $bolt -l="$run_flags" --cpuset $cpuset -i $nums -d "No" &
    image_name=$(python3 $script2 -w $workload -r $repo -b $branch -n="$build_flags" --bolt $bolt)

    # $workload_dir_name is used to locale the workload dir.
    # $workload is used to generate the result.zip.
    case $workload in 
      *webtooling*)
        workload_dir_name="webtooling" ;;
      *ghost*)
        workload_dir_name="ghost" ;;
      *ssr*) 
        workload_dir_name="ssr-calcom"
        image_name="ssr_calcom:client" ;;
      *nodeio*) ;;
      *base64*) 
        workload_dir_name="base64" ;;
      *fc_startup*) 
        workload_dir_name="fc-startup" ;;
    esac

    # Start collecting emon data
    cd emon
    ./$emon_script $image_name $nums $machine $workload_dir_name

    # Wait for generating result.json
    result_dir=$workload_path/$workload_dir_name/results
    until check_json $result_dir; do
      echo "Wait the results..."
      sleep 2
    done

    # Precess emon data
    tps=$(cat $result_dir/*.json | grep "Total TPS" | awk -F'"' '{print $4}')
    rps=$(cat $result_dir/*.json | grep "Total RPS" | awk -F'"' '{print $4}')

    if [ -n "$tps" ]; then rps=$tps
    elif [ -n "$rps" ]; then rps=$rps
    else echo "No TPS/RPS in results. Please check the workload-run."; exit 1
    fi
    echo "TPS is $rps"; 
    ./$emon_process_script $rps $machine $workload $result_dir

    exit 0
fi

echo "Please use true parameters: perf[-p] or emon[-e]."
