#! /usr/bin/python
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


import sys
import os

server_path = sys.argv[1]
error_path = sys.argv[2]
image = sys.argv[3]
flags = sys.argv[4]


f1 = open(server_path, "r")
servers = {}

# Load all server containers into servers
for line in f1:
  line = line.strip()
  parts = line.split()
  servers[parts[1]] = parts[0]
f1.close()
# print(servers.keys())

# Load all error containers into errors
f2 = open(error_path, "r")
errors = []
for line in f2:
  line = line.strip()
  errors.append(line)
f2.close()

# Detect error container and restart
for name in errors:
  print(name)
  if name in servers.keys():
    print(f"Here is an error server conatiner [{name}] should be restarted.")
    
    # Remove the error container
    cmd1 = "docker rm " + name
    os.system(cmd1)
    
    # Restart
    cmd2 = f"docker run --cpus=2 --cpuset-cpus={servers[name]} --privileged --name {name} -td --runtime=runc {image} bash -c \"/calcom/cal.com/docker-entrypoint.sh {flags}\""
    print(cmd2)
    os.system(cmd2)
    
    
