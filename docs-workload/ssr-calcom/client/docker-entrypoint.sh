#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


# Env Variables
NUM_REQ="${1:-100000}"
CONCURRENCY="${2:-1}"
addr="${3:-127.0.0.1}"

# Start Bench
# h2load --h1 -n$NUM_REQ -c$CONCURRENCY http://${addr}:3000/apps
ab -r -n$NUM_REQ -c$CONCURRENCY http://${addr}:3000/apps