#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


image_name=$1
boltfile_name=$2
context_path=$3
container_name=${4:-"bolt-collect"}

docker rm $container_name

docker run --cpus=2 --privileged -td --name $container_name $image_name bash -c ./start.sh

source_file="$container_name:/home/ubuntu/perf.fdata.gz"
target_file="$context_path/$boltfile_name"

# Loop to check the container status until it exits
while true; do
  container_status=$(docker ps -f name="$container_name" --format "{{.Status}}")

  # If the container status is empty, it means the container has exited
  if [ -z "$container_status" ]; then
    echo "Container $container_name has exited."
    break
  fi

  echo -n "."
  sleep 1
done

# Execute docker cp command to copy the file
docker cp "$source_file" "$target_file"
echo "Copied file from $source_file to $target_file."
cp $target_file ../generate_bolt/patches/$boltfile_name

# For upload to server
cp $target_file `pwd`/$boltfile_name