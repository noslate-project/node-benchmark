#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

set -e

nums=$1
image=$2
node_version=$3
protocol=$4
opt_type=$5
machine=$6
run_flags=$7
perf_args=$8

container_name="perf-container"
perf_image_name=${image/ghost/ghost-perf}
path=$(pwd | sed 's/tools/ghost/')

echo "Tag a new image $perf_image_name from $image for profiling."
docker tag $image $perf_image_name

if [ $nums -gt 1 ]; then
  echo "Begin run no-profiling containers."
  mkdir -p $path/results
  $path/ghostjs.sh $((nums-1)) $image $node_version $protocol $opt_type $run_flags &

  while true; do
    count=$(docker ps -q -f ancestor=$image | wc -l)
    if [ $count -eq $((nums-1)) ]; then
      echo "Warm up container now."
      break
    fi
    sleep 1
  done

  runc_name=$(docker ps --format "{{.Names}}" | grep "runc")
  first_name=$(echo $runc_name | cut -d " " -f 1)

  CONTINUE=true
  while $CONTINUE; do
    LOGS=$(docker logs $first_name)

    if [[ "$LOGS" == *"Running"* ]]; then
      echo "Run $container_name now."
      CONTINUE=false
    else
      echo "Containers are warming up..."
      sleep 2
    fi
  done
fi

cores=$(( $(nproc) - 1 ))
cmd="/home/ghost/Ghost/breakdown.sh $run_flags $perf_args"

echo "Run profiling container with: $cmd"
echo "docker run -td --privileged --cpus=2 --cpuset-cpus=$opt_type --name $container_name $perf_image_name bash -c $cmd"
if [ $opt_type = "opt" ]; then
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
mkdir -p $path/breakdown-results
docker cp $container_name:/home/ghost/Ghost/output.svg $path/breakdown-results/output.svg
docker cp $container_name:/home/ghost/Ghost/perf.report $path/breakdown-results/perf.report
docker cp $container_name:/home/ghost/Ghost/perf.profile $path/breakdown-results/perf.profile
docker cp $container_name:/home/ghost/Ghost/result.txt $path/breakdown-results/result.txt
docker cp $container_name:/home/ghost/Ghost/perf.data.tar.bz2 $path/breakdown-results/perf.data.tar.bz2
docker cp $container_name:/home/ghost/Ghost/cycles.txt $path/breakdown-results/cycles.txt
docker cp $container_name:/home/ghost/Ghost/perf.data $path/breakdown-results/perf.data
docker cp $container_name:/home/ghost/Ghost/perf.data.jitted $path/breakdown-results/perf.data.jitted

cd $path
zip -r ghost-breakdown-$machine-$(date +%Y-%m-%d_%H-%M-%S).zip ./breakdown-results

docker logs $container_name
docker rm $container_name