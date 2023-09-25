FROM ubuntu:22.04

WORKDIR /

RUN apt-get update && apt-get upgrade -y && apt-get install -y apache2-utils
# RUN apt-get install -y nghttp2-client

WORKDIR /home

COPY docker-entrypoint.sh ./docker-entrypoint.sh
RUN ["chmod", "+x", "/home/docker-entrypoint.sh"]
