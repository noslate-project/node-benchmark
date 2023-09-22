#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# set -e

nums=""
image=""  # server image name
run_flags=""
perf_args=""

# For ssr, emon is always false and cpuset is always true.
# The option exists only for less modification of python scripts.
emon="false"
cpuset="true"

machine=""
path=$(pwd | sed 's/tools/ssr-calcom/')

while getopts "n:i:r:m:p:c:e:" opt
do
  case $opt in
    n) nums=$OPTARG ;;
    i) image=$OPTARG ;;
    r) run_flags=$OPTARG ;;
    e) emon=$OPTARG ;;
    m) machine=$OPTARG ;;
    p) perf_args=$OPTARG ;;
    c) cpuset=$OPTARG ;;
    ?) echo "Invalid option: -$OPTARG" ;;
  esac
done

# Server
server_container_name="server-perf"
server_perf_image_name=${image/ssr_calcom/ssr_calcom-perf}
echo "Tag a new image $server_perf_image_name from $image for profiling."
docker tag $image $server_perf_image_name

# Client
client_image="ssr_calcom:client"
client_container_name="client-perf"
client_perf_image_name="ssr_calcom-perf:client"
echo "Tag a new image $client_perf_image_name from $client_image for profiling."
docker tag $client_image $client_perf_image_name

# clean env
docker rm $server_container_name
docker rm $client_container_name

# instance nums is not 1
if [ $nums -gt 1 ]; then
  echo "Begin run no-profiling containers."
  $path/ssr.sh $((nums-1)) $image "$run_flags" &

  while true; do
    count=$(docker ps -q -f ancestor=$client_image | wc -l)
    if [ $count -eq $((nums-1)) ]; then
      echo "Run $server_container_name and $client_container_name now."
      break
    fi
    sleep 1
  done
  sleep 5
fi

cores=$(nproc)

# Server
cmd_server="/calcom/cal.com/breakdown.sh \"$run_flags\" \"$perf_args\""
echo "Run profiling server container with: $cmd_server"
server_cpu=$((cores*3/4 - 1))
docker run -td --privileged --cpus=2 --cpuset-cpus=$server_cpu,0 --name $server_container_name $server_perf_image_name bash -c "$cmd_server"

# When perf-server is ok, then start perf-client
CONTINUE=true
while $CONTINUE; do
  if docker ps --filter "name=$server_container_name" --format "{{.Names}}" | grep -q "$server_container_name"; then
    server_logs=$(docker logs $server_container_name)
  else
    # Sometimes perf-container may failed to start.
    echo "There is no $server_container_name. Maybe the container exited abnormally."
    docker rm $server_container_name
    docker run -td --privileged --cpus=2 --cpuset-cpus=$server_cpu,0 --name $server_container_name $server_perf_image_name bash -c "$cmd_server"
    echo "Restart server-perf..."
    sleep 2
  fi

  # detect server is ready or not
  if [[ "$server_logs" == *"http://localhost:3000"* ]]; then
    echo "Run $client_container_name now."
    CONTINUE=false
  else
    echo "Perf server is starting..."
    sleep 2
  fi
done

# Client
ip_addr=$(docker inspect $server_container_name | grep \"IPAddress\" | awk '{print $2}' | sed 's/[,\"]//g' | tail -n 1)
cmd_client="/home/docker-entrypoint.sh 5000 100 $ip_addr"
echo "Run profiling client container with: $cmd_client"
client_cpu1=$((cores/4))
client_cpu2=$((cores - 1))
docker run -td --privileged --cpus=2 --cpuset-cpus=$client_cpu2,$client_cpu1 --name $client_container_name $client_perf_image_name bash -c "$cmd_client"

echo "perf-server is still running"
while [ -n "$(docker ps -q -f name=$server_container_name -f status=running)" ]; do
  echo -n '*'
  sleep 1
done
echo "Completed!"

# Copy file to local
rm -rf $path/breakdown-results
mkdir -p $path/breakdown-results
docker cp $server_container_name:/calcom/cal.com/output.svg $path/breakdown-results/output.svg
docker cp $server_container_name:/calcom/cal.com/perf.report $path/breakdown-results/perf.report
docker cp $server_container_name:/calcom/cal.com/perf.profile $path/breakdown-results/perf.profile
docker cp $server_container_name:/calcom/cal.com/result.txt $path/breakdown-results/result.txt
docker cp $server_container_name:/calcom/cal.com/perf.data.tar.bz2 $path/breakdown-results/perf.data.tar.bz2
docker cp $server_container_name:/calcom/cal.com/cycles.txt $path/breakdown-results/cycles.txt
docker cp $server_container_name:/calcom/cal.com/perf.data $path/breakdown-results/perf.data
docker cp $server_container_name:/calcom/cal.com/perf.data.jitted $path/breakdown-results/perf.data.jitted

cd $path
zip -r breakdown.zip ./breakdown-results

docker rm $server_container_name
docker rm $client_container_name