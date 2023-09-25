ARG BASIC_IMAGE="ubuntu:22.04"
FROM ${BASIC_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.1"
LABEL IMAGE_BUILD_TYPE="build_from_source_code"

# Get essential files.
RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y build-essential git curl sudo \
    ca-certificates cmake ninja-build libjemalloc-dev \
    ssh wget vim nano gosu autoconf automake bison openssl \
    gcc-10 g++-10 cpp-10
RUN apt-get remove -y unattended-upgrades
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10

# Create workdir.
RUN mkdir -p /home/ubuntu/work

# Source code url for Node.js.
ARG NODEJS_URL="https://github.com/nodejs/node.git"
ARG LLVM_URL="https://github.com/llvm/llvm-project"
ARG NODEJS_VERSION="v18.14.2"
ARG TARGET_PLATFORM="x64"
ARG LLVM_VERSION="release/14.x"
ARG BOLT_USE="false"
ARG BOLT_FILE=
ARG PGO_USE="false"
ARG PGO_TYPE="use"
ARG PGO_FILE=${NODEJS_VERSION}.patch

# Clone Node.js source code and apply optmizations patch.
WORKDIR /home/ubuntu/work
RUN git clone --depth 1 --branch ${NODEJS_VERSION} ${NODEJS_URL} node

# Patch - PGO
WORKDIR /home/ubuntu/work
RUN mkdir pgo-bolt
COPY patches pgo-bolt/
WORKDIR /home/ubuntu/work/pgo-bolt
RUN ./apply_pgo.sh ${PGO_USE} ${PGO_TYPE} ${PGO_FILE}

# Build node.js binary.
ARG NODE_BUILD_FLAGS=
WORKDIR /home/ubuntu/work/node
RUN CC='gcc -no-pie -fno-PIE -fno-reorder-blocks-and-partition -fcf-protection=none -Wl,--emit-relocs -Wl,-znow ' \
    CXX='g++ -no-pie -fno-PIE -fno-reorder-blocks-and-partition -fcf-protection=none -Wl,--emit-relocs -Wl,-znow ' \
    ./configure ${NODE_BUILD_FLAGS} && \
    make -j$((`nproc`-1)) && \
    mkdir node_bin && \
    make install PREFIX=./node_bin

# Apply node.js binary.
WORKDIR /home/ubuntu/work
RUN cp -r /home/ubuntu/work/node/node_bin/bin /usr/local/ && \
    cp -r /home/ubuntu/work/node/node_bin/lib /usr/local/ && \
    cp -r /home/ubuntu/work/node/node_bin/share /usr/local/ && \
    cp -r /home/ubuntu/work/node/node_bin/include /usr/local/

# Patch - BOLT
WORKDIR /home/ubuntu/work/pgo-bolt
RUN ./apply_bolt.sh ${BOLT_USE} ${LLVM_VERSION} ${LLVM_URL} ${BOLT_FILE}

WORKDIR /home/ubuntu/work
CMD /usr/local/bin/node
