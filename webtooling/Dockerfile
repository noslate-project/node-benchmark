FROM ubuntu:22.04
LABEL authors="lei.a.shi@intel.com"

RUN apt-get update && \
    apt-get install -y git wget xz-utils

# node version
ARG VERSION="v18.12.0"
ARG DISTRO="linux-x64"

# install node
RUN wget https://nodejs.org/dist/${VERSION}/node-${VERSION}-${DISTRO}.tar.xz \
    && mkdir -p /usr/local/lib/nodejs \
    && tar -xJvf node-${VERSION}-${DISTRO}.tar.xz -C /usr/local/lib/nodejs \
    && rm node-${VERSION}-${DISTRO}.tar.xz


ENV PATH=/usr/local/lib/nodejs/node-${VERSION}-${DISTRO}/bin:$PATH

ARG WEB_TOOLING_URL="https://github.com/v8/web-tooling-benchmark.git"
RUN git clone ${WEB_TOOLING_URL} && \
	cd /web-tooling-benchmark/ && npm install

WORKDIR /web-tooling-benchmark
