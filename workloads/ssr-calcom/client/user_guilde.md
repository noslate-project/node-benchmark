This is the user guide to download webtooling workload and compose the Dockerfile:

```
FROM ubuntu:22.04

WORKDIR /

RUN apt-get update && apt-get upgrade -y && apt-get install -y apache2-utils
# RUN apt-get install -y nghttp2-client

WORKDIR /home

COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN ["chmod", "+x", "/home/docker-entrypoint.sh"]


```

The docker-entrypoint.sh is the entry point of the container. It shall invoke ab tool as client.
Please refer to below instructions to compose the `entrypoint.sh`
```
# Env Variables
NUM_REQ="${1:-100000}"
CONCURRENCY="${2:-1}"
addr="${3:-127.0.0.1}"

# Start Bench
# h2load --h1 -n$NUM_REQ -c$CONCURRENCY http://${addr}:3000/apps
ab -r -n$NUM_REQ -c$CONCURRENCY http://${addr}:3000/apps
```