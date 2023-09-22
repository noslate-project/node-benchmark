#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# This script will read the latest tag from the node repo
# It will use curl and sed or awk to parse the JSON response from the GitHub API
# It will print the tag name to the standard output

mode=$1

# Define the repo URL
REPO_URL="https://api.github.com/repos/nodejs/node/tags"
if [ $mode = "build" ]; then
    proxy_url="http://child-prc.intel.com:913/"
else
    # proxy_url=$(echo $https_proxy)
    proxy_url="http://child-prc.intel.com:913/"
fi

# Use curl to get the JSON response
RESPONSE=$(curl -x $proxy_url -s $REPO_URL)

# Use sed or awk to extract the first tag name
# The awk command will split the matched line by double quotes and print the fourth field
TAG_NAME=$(echo $RESPONSE | awk -F\" '/"name": "v[0-9.]+"/ {print $4; exit}')

while [ -z "${TAG_NAME}" ]; do
  # Sleep for 1 second to avoid hitting the rate limit too frequently
  sleep 2
  # Retry the curl command and assign the response to RESPONSE
  RESPONSE=$(curl -x ${proxy_url} -s ${REPO_URL})
  # Assign the tag name to TAG_NAME again
  TAG_NAME=$(echo ${RESPONSE} | awk -F\" '/"name": "v[0-9.]+"/ {print $4; exit}')
done

# Print the tag name
echo $TAG_NAME
