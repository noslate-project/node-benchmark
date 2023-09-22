#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


if [ $1 = "false" ]; then
  echo "No PGO-Use"
  exit 0
else
  if [ -z "$2" ]; then
    echo "Usage: $0 generate|use PGO-file"
    exit 1
  fi

  # pgo_generate.patch or pgofile.tar.gz
  file_name=$3

  # Execute different statements based on the first argument
  case "$2" in
    generate)
      # Execute a statement
      cp $file_name /home/ubuntu/work/node
      cd /home/ubuntu/work/node/
      if ! git apply $file_name ; then
          echo "Error when apply patch: $file_name"
          exit 2
      fi
      echo "Apply patch: $file_name"
      cd ..
      ;;
    use)
      # cd /home/ubuntu/work/pgo/patches
      cd /home/ubuntu/work/pgo
      tar xzf $file_name
      cp -rf -v pgodata/home/ubuntu/work/node/out /home/ubuntu/work/node/
      echo "PGO-patch files is OK."
      ;;
    *)
      # Invalid argument
      echo "Invalid argument: $2"
      exit 2
      ;;
  esac
fi
