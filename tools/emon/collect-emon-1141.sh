#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


IMAGE="${1:-webtooling}"
NUM_CONTAINERS="${2:-1}"
MACHINE="${3:-ICX}"
WORKLOAD="${4:-webtooling}"

# Verify EMON is working first
source /opt/intel/sep/sep_vars.sh
output=$(bash -c 'emon -v' 2>&1)
grep Error <<< "$output"
error_found=$?
if [[ ${error_found} -eq 0 ]]; then
    echo "EMON is broken or not installed"
    echo "Exiting automation..."
    exit 1
else
    echo "EMON works"
    echo "Proceeding with run..."
fi

case $MACHINE in
  *AMD*) edp_architecture_codename="amd" ;;
  *ICX*) edp_architecture_codename="icelake" ;;
  *SPR*) edp_architecture_codename="sapphirerapids" ;;
  *Alderlake*) edp_architecture_codename="gracemont" ;;
  *) echo "[Error]: Unknown machine!" ; exit 1 ;;
esac

if [ -z "${edp_architecture_codename}" ]
then
        echo "Architecture codename is not set!"
        echo "Please set the edp_architecture_name variable and rerun"
        exit 1
fi

help()  {
cat << EOF
Usage: $0 <docker-image-name> <num-instances> <machine> <workload>
   Example: collect-emon-ghost.sh webtooling-intel-v18.14.2:base 64 ICX webtooling
   Description:
        <docker-image-name>: Name of container images to run.
        <num-instances>: the number of instances to run.
        <machine>: Running server.
        <workload>: Name of workload.
EOF
}

 # Verify enough arguments
if [ $# != 4 ]; then
    echo >&2 "error: Not enough arguments [$@]"
    help
    exit 1
fi

echo "Waiting for ${NUM_CONTAINERS} containers launched for ${IMAGE}"
while true
do
     containers_launched=$(docker ps -a -f ancestor=$IMAGE | grep "Up" | wc -l)
     [ "$containers_launched" -eq "$NUM_CONTAINERS" ] && break
     sleep 3s
done

# checking benchmarking status
c1=()
s1=()
index=0
totalcontainers=$(sudo docker ps -q -f ancestor=$IMAGE | wc -l)
for container in $(sudo docker ps -q -f ancestor=$IMAGE); do
	c1[$index]=$container
	s1[$index]=1
	index=$((index+1))
done

echo "Initializing containers readiness status..."
for ((i=0; i <$totalcontainers; i++))
do
	echo "${c1[$i]}=${s1[$i]}"
done

# ghost need to warmup
if [ "$WORKLOAD" = "ghost" ]; then
  MOUNTED_DIR=`ls -d /tmp/ghostjsM.*`
  echo "---------------------------------------"
  echo "Waiting for all related containers to warmup"
  while true
  do
	  warmup_done=$(ls ${MOUNTED_DIR}/warmup_done | wc -l)
	  ((warmup_done == $totalcontainers)) && break
	  sleep 2s
  done
fi

echo "------------------------------------------------"
echo "Collecting EMON collection for ${edp_architecture_codename}"
echo "------------------------------------------------"

echo "Starting CPU utilization collection..."
./start-sar.sh -i 1 -o "./cpu-utils.txt" &

start_emon_time=$(date)
echo "Start EMON: ${start_emon_time}" > emon.log

nohup emon -collect-edp > emon.dat 2>&1 &

#sleep $duration
while true
do
    #echo "Verify that the containers are exited"
    containers_exited=$(docker ps -a | grep "$IMAGE" | grep "Exited" | wc -l)
    #echo -n "."
    [ "$containers_exited" -gt "0" ] && break #stop emon when one container exited
    sleep 1s
done

emon -stop
stop_emon_time=$(date)
echo "Stop EMON: ${stop_emon_time}" >> emon.log
echo "Stopping CPU utilization collection..."
./stop-sar.sh
emon -v > emon-v.dat
emon -M > emon-M.dat
sudo dmidecode > dmidecode.txt

if [ ${edp_architecture_codename} == "cascadelake" ] || [ ${edp_architecture_codename} == "icelake" ] || [ ${edp_architecture_codename} == "sapphirerapids" ]; then
  # CLX, ICX, SPR
  echo "EMON Command: nohup emon -i /opt/intel/sep/config/edp/${edp_architecture_codename}_server_events_private.txt > emon.dat 2>&1" >> emon.log

elif [ ${edp_architecture_codename} == "amd" ] || [ ${edp_architecture_codename} == "alderlake" ]; then
  # AMD, Alderlake
  echo "EMON Command: nohup emon -i /opt/intel/sep/config/edp/${edp_architecture_codename}_events_private.txt > emon.dat 2>&1" >> emon.log
fi

echo "------------------------------------------------"
lscpu > lscpu.txt

# sleep $duration
echo "Wait all container exited."
while true
do
  #echo "Verify that the containers are exited"
  containers_exited=$(docker ps -a | grep "$IMAGE" | grep "Exited" | wc -l)
  echo -n "."
  #exit when all containers exited
  [ "$containers_exited" -eq "$NUM_CONTAINERS" ] && break #exit when all containers exited
  test -z "$(docker ps -a | grep "$IMAGE")" && break #exit when no IMAGE containers
  sleep 1s
done
