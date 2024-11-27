# Set up an Ubuntu image with 'web tooling' installed
ARG BASIC_IMAGE="node:latest"
FROM ${BASIC_IMAGE}
WORKDIR /home/ubuntu/

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.1"

# URL for web tooling test
ARG WEB_TOOLING_URL="https://github.com/v8/web-tooling-benchmark"

RUN apt-get update && apt-get upgrade -y && apt-get install --assume-yes apt-utils
RUN apt-get install -y build-essential git curl python3 g++ make sudo
RUN apt-get remove -y unattended-upgrades

# Clone and install web-tooling-benchmark.
RUN git clone --depth 1 --branch master ${WEB_TOOLING_URL}
RUN cd web-tooling-benchmark/ && npm install --unsafe-perm

# Install perf tools
RUN apt-get update && apt-get install -y flex python2 linux-tools-`uname -r`
ARG perf_version="linux-6.2"

# Download and build linux tools, remaining perf-archive
RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${perf_version}.tar.xz && \
    tar xf ${perf_version}.tar.xz && \
    cd ${perf_version}/tools/perf && make CC=gcc ARCH=x86_64 && \
    cp perf-archive /home/ubuntu/web-tooling-benchmark/perf-archive && \
    rm -rf ${perf_version} ${perf_version}.tar.xz

# Clone FlameGraph and breakdown.sh
ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}
COPY ./common/breakdown.sh /home/ubuntu/web-tooling-benchmark/breakdown.sh
COPY ./common/perf_module_breakdown.py /home/ubuntu/web-tooling-benchmark/perf_module_breakdown.py

WORKDIR /home/ubuntu/web-tooling-benchmark/
