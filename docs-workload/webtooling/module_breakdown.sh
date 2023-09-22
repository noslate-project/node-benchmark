#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


set -e

nums=""
image=""
run_flags=""
perf_args=""
emon="false"
machine=""
cpuset=""
path=$(pwd | sed 's/tools/webtooling/')

while getopts "n:i:r:e:m:c:p:" opt
do
  case $opt in
    n) nums=$OPTARG ;;
    i) image=$OPTARG ;;
    r) run_flags=$OPTARG ;;
    e) emon=$OPTARG ;;
    m) machine=$OPTARG ;;
    c) cpuset=$OPTARG ;;
    p) perf_args=$OPTARG ;;
    ?) echo "Invalid option: -$OPTARG" ;;
  esac
done

# Collect Emon Data
if [ $emon = "true" ]; then
  echo "Collect Emon Data of webtooling on $machine."

  case $machine in
    *AMD*) ARCH_NAME="amd" ;;
    *ICX*) ARCH_NAME="icelake_server" ;;
    *SPR*) ARCH_NAME="sapphirerapids_server" ;;
    *) echo "[Error]: Unknown machine!" ; exit 1 ;;
  esac

  EMON_EVENTS_FILE="${ARCH_NAME}_events_private.txt"

  sockets_num=$(lscpu | grep Socket | awk -F: '{print $2}')
  edp_architecture_sockets=${sockets_num//' '/''}"s"
  
  EDP_METRIC_FILE="${ARCH_NAME}_${edp_architecture_sockets}_private.xml"
  EDP_CHART_FORMAT="chart_format_${ARCH_NAME}_private.txt"

  if [ $cpuset = "true" ]; then
    $path/webtooling.sh $nums $image --node-flags "$run_flags" --cpuset --emon "$EMON_EVENTS_FILE;$EDP_METRIC_FILE;$EDP_CHART_FORMAT"
  else
    $path/webtooling.sh $nums $image --node-flags "$run_flags" --emon "$EMON_EVENTS_FILE;$EDP_METRIC_FILE;$EDP_CHART_FORMAT"
  fi

  cd $path
  # tar zcvf emon.tar.gz ./results
  zip -r emon.zip ./results
  exit 0
fi

################################################################################################################
################################################# Module BreakDown #############################################
################################################################################################################
container_name="perf-container"
perf_image_name=${image/webtooling/webtooling-perf}

echo "Tag a new image $perf_image_name from $image for profiling."
docker tag $image $perf_image_name

if [ $nums -gt 1 ]; then
  echo "Begin run no-profiling containers."
  if [ $cpuset = "true" ]; then
    $path/webtooling.sh $((nums-1)) $image --node-flags "$run_flags" --cpuset &
  else
    $path/webtooling.sh $((nums-1)) $image --node-flags "$run_flags" &
  fi

  while true; do
    count=$(docker ps -q -f ancestor=$image | wc -l)
    if [ $count -eq $((nums-1)) ]; then
      echo "Run $container_name now."
      break
    fi
    sleep 1
  done
fi

cores=$(( $(nproc) - 1 ))
cmd="/home/ubuntu/web-tooling-benchmark/breakdown.sh $run_flags $perf_args"

echo "Run profiling container with: $cmd"
echo "docker run -td --privileged --cpus=2 --cpuset-cpus="$cores,0" --name $container_name $perf_image_name bash -c $cmd"

if [ $cpuset = "true" ]; then
  docker run -td --privileged --cpus=2 --cpuset-cpus=$cores,0 --name $container_name $perf_image_name bash -c $cmd
else
  docker run -td --privileged --cpus=2 --name $container_name $perf_image_name bash -c $cmd
fi

echo "perf-container is still running"
while [ -n "$(docker ps -q -f name=$container_name -f status=running)" ]; do
  echo -n '*'
  sleep 1
done
echo "Completed!"

# Copy file to local
rm -rf $path/breakdown-results
mkdir -p $path/breakdown-results
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/output.svg $path/breakdown-results/output.svg || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/perf.data $path/breakdown-results/perf.data || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/perf.data.jitted $path/breakdown-results/perf.report || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/perf.report $path/breakdown-results/perf.report || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/perf.profile $path/breakdown-results/perf.profile || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/result.txt $path/breakdown-results/result.txt || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/perf.data.tar.bz2 $path/breakdown-results/perf.data.tar.bz2 || true
docker cp $container_name:/home/ubuntu/web-tooling-benchmark/result.txt $path/breakdown-results/result.txt || true

cd $path
zip -r webtooling-breakdown-$machine-$(date +%Y-%m-%d_%H-%M-%S).zip ./breakdown-results

docker logs $container_name
docker rm $container_name