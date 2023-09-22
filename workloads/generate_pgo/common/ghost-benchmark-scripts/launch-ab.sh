#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


COUNT=$1
COUNT=${COUNT:-1}

START_PORT=$2
START_PORT=${START_PORT:-2368}

SAME_PORT=$3

WHERE="$4"

PREFIX="$5"

PROTOCOL="http"
if test "x$6x" != "xx"; then
  PROTOCOL="$6"
fi

TIMEOUT=$7
TIMEOUTX=$7
SCRIPTS_DIR=$8
ITER_NUM=$9

if test "x${TIMEOUT}x" != "xx"; then
  TIMEOUT="-t ${TIMEOUT}"
fi

# Warmup
for ((Nix = 0; Nix < ${COUNT}; Nix++)); do
  PORT_OFFSET="${Nix}"
  if test "x${SAME_PORT}x" != "xx"; then
    PORT_OFFSET=0
  fi
  ab -r -n 5000 -c 25 "${PROTOCOL}"://localhost:$[${START_PORT} + ${PORT_OFFSET}]/ > /dev/null 2>&1 &
  echo "Warmup: ${Nix}: $!"
done
wait

echo "Warmup is done."
echo "Sleeping for ${TIMEOUTX} seconds... or Press [Enter] to start measurements immediately..."
read ${TIMEOUT}

START_TIME="$(date)"
# Measurement
for ((Nix = 0; Nix < ${COUNT}; Nix++)); do
  LOG_DIR="${WHERE}/${PREFIX}.$(printf "%03d" ${Nix})"
  PORT_OFFSET="${Nix}"
  if test "x${SAME_PORT}x" != "xx"; then
    PORT_OFFSET=0
  fi
  ab -r -n 20000 -c 50 "${PROTOCOL}"://localhost:$[${START_PORT} + ${PORT_OFFSET}]/ > "${LOG_DIR}/ab" 2>&1 &
  echo "Measurement: ${Nix}: $!"
done

echo "---------------------------------"
echo "Running iteration #${ITER_NUM}..."
echo "---------------------------------"

# collect cpu util
#echo "Starting CPU utilization collection..."
#${SCRIPTS_DIR}/start-sar.sh -i 1 -o "${WHERE}/cpu-util-${COUNT}.txt" &
touch /host/warmup_done/${HOSTNAME} || true

wait

#echo "Stopping CPU utilization collection..."
#${SCRIPTS_DIR}/stop-sar.sh

echo "began: ${START_TIME}"
echo "ended: $(date)"
