#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

nums=""
image=""
perf_args=""
path=$(pwd | sed 's/tools/base64/')

while getopts "n:i:p:" opt
do
  case $opt in
    n) nums=$OPTARG ;;
    i) image=$OPTARG ;;
    p) perf_args=$OPTARG ;;
    ?) echo "Invalid option: -$OPTARG" ;;
  esac
done

container_name="perf-container"
docker rm $container_name

cmd="/home/breakdown.sh $perf_args"
echo "Run profiling container with: $cmd"

docker run -td --privileged --cpus=2 --name $container_name $image bash -c $cmd

echo "perf-container is still running"
while [ -n "$(docker ps -q -f name=$container_name -f status=running)" ]; do
  echo -n '*'
  sleep 1
done
echo "Completed!"

rm -rf $path/breakdown-results
mkdir -p $path/breakdown-results
docker cp $container_name:/home/output.svg $path/breakdown-results/output.svg
docker cp $container_name:/home/perf.data $path/breakdown-results/perf.data
docker cp $container_name:/home/perf.report $path/breakdown-results/perf.report
docker cp $container_name:/home/perf.profile $path/breakdown-results/perf.profile
docker cp $container_name:/home/perf.data.tar.bz2 $path/breakdown-results/perf.data.tar.bz2
docker cp $container_name:/home/result.txt $path/breakdown-results/result.txt

cd $path
zip -r breakdown.zip ./breakdown-results

docker rm $container_name
