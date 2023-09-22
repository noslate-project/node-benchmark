This is the user guide to install and apply BOLT optimization for Node.js. This opt can make node.js obtaining branch opt information for all supported workloads so as to run workloads faster.

```

FROM ubuntu:22.04

ENV USERNAME="ubuntu"
ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1

# Install required packages that are not included in ubuntu core image
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    mariadb-server \
    wget \
    vim \
    sysstat \
    sudo \
    build-essential git curl \
    ca-certificates cmake ninja-build libjemalloc-dev \
    ssh vim nano gosu autoconf automake bison openssl \
    gcc-10 g++-10 cpp-10 \
    nginx \
    apache2-utils && \
    apt-get remove -y unattended-upgrades && \
    rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
--slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10

# Create new Linux account
RUN useradd -rm -d /home/${USERNAME} -s /bin/bash -g root -G sudo -u 1001 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

###############################################################################################
################################### Install Ghost-HTTP ########################################
###############################################################################################

# Switch to ${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Upload ghost.dump database
COPY common/ghost.dump /home/${USERNAME}

# Configure mariadb and install ghost database
RUN echo "soft nofile 65536\nhard nofile 65536" | sudo tee -a /etc/security/limits.conf
RUN echo "\n[mysqld]\nopen_files_limit = 65536\nmax_connections = 10240" | sudo tee -a /etc/mysql/my.cnf

RUN sudo service mariadb start && \
    sleep 1 && \
    sudo mysqladmin -u root password "" && \
    sudo mysql -u root -e "use mysql; ALTER USER 'root'@'localhost' IDENTIFIED BY ''" && \
    sudo mysql -u root -e "FLUSH PRIVILEGES" && \
    sudo mysql -u root -e "source /home/${USERNAME}/ghost.dump" && \
    sudo service mariadb stop

# Download node v12.22.1 which is needed to install ghost, but will be removed afterwards
RUN wget https://nodejs.org/download/release/v12.22.1/node-v12.22.1-linux-x64.tar.xz

# Untar node v12.22.1
RUN tar xvf node-v12.22.1-linux-x64.tar.xz
ENV ORIGINAL_PATH="${PATH}"
ENV PATH="/home/${USERNAME}/node-v12.22.1-linux-x64/bin:${ORIGINAL_PATH}"

# Install ghost
WORKDIR /home/${USERNAME}
RUN mkdir ghost-cli
WORKDIR /home/${USERNAME}/ghost-cli
RUN npm install ghost-cli@1.19.0
WORKDIR /home/${USERNAME}
RUN mkdir Ghost
WORKDIR /home/${USERNAME}/Ghost
RUN /home/${USERNAME}/ghost-cli/node_modules/.bin/ghost install 4.4.0 local
RUN /home/${USERNAME}/ghost-cli/node_modules/.bin/ghost status
COPY --chown=${USERNAME}:root common/config.production.json /home/${USERNAME}/Ghost

WORKDIR /home/${USERNAME}

# Remove node v12.22.1
RUN rm -rf /home/${USERNAME}/node-v12.22.1-linux-x64
RUN rm /home/${USERNAME}/node-v12.22.1-linux-x64.tar.xz

# Copy in scripts to run the workload
RUN mkdir /home/${USERNAME}/ghost-benchmark-scripts
COPY --chown=${USERNAME}:root common/ghost-benchmark-scripts /home/${USERNAME}/ghost-benchmark-scripts
COPY --chown=${USERNAME}:root common/quickrun.sh /home/${USERNAME}/Ghost
COPY --chown=${USERNAME}:root common/entrypoint.sh /usr/local/bin/entrypoint.sh

#nginx
RUN mkdir /home/${USERNAME}/nginx
COPY --chown=${USERNAME}:root common/nginx.conf.http  /home/${USERNAME}/nginx/nginx.conf

################################################################################################
#################################### Install Webtooling ########################################
################################################################################################
WORKDIR /home/${USERNAME}
RUN sudo -E apt-get update
RUN sudo -E apt-get upgrade -y
RUN sudo -E apt-get install -y nodejs npm
RUN sudo -E apt-get remove -y unattended-upgrades

ARG WEB_TOOLING_URL="https://github.com/v8/web-tooling-benchmark.git"
RUN git clone --depth 1 --branch master ${WEB_TOOLING_URL}
WORKDIR /home/${USERNAME}/web-tooling-benchmark/
RUN npm install --unsafe-perm

RUN sudo apt-get remove -y nodejs npm
WORKDIR /home/${USERNAME}

################################################################################################
#################################### Install node.js ###########################################
################################################################################################
# Clone node.js source code
RUN mkdir -p work
WORKDIR /home/${USERNAME}/work
ARG NODEJS_VERSION="v18.14.2"
ARG NODEJS_URL="https://github.com/nodejs/node.git"
ARG PGO_USE="false"
ARG PGO_TYPE="use"
ARG PGO_FILE=${NODEJS_VERSION}.patch
RUN git clone --depth 1 --branch ${NODEJS_VERSION} ${NODEJS_URL} node

# Generate PGO-file
WORKDIR /home/ubuntu/work
RUN mkdir pgo
COPY patches pgo/
WORKDIR /home/ubuntu/work/pgo
RUN ./apply_pgo.sh ${PGO_USE} ${PGO_TYPE} ${PGO_FILE}

# Build node.js binary without `pgo` and `bolt`
ARG NODE_BUILD_FLAGS=""
WORKDIR /home/${USERNAME}/work/node
RUN CC='gcc -no-pie -fno-PIE -fno-reorder-blocks-and-partition -fcf-protection=none -Wl,--emit-relocs -Wl,-znow ' \
    CXX='g++ -no-pie -fno-PIE -fno-reorder-blocks-and-partition -fcf-protection=none -Wl,--emit-relocs -Wl,-znow ' \
    ./configure ${NODE_BUILD_FLAGS} && \
    make -j$((`nproc`-1))

# Install llvm
WORKDIR /home/${USERNAME}/work
ARG LLVM_URL="https://github.com/llvm/llvm-project.git"
ARG LLVM_VERSION="release/14.x"

RUN git clone --depth 1 --branch ${LLVM_VERSION} ${LLVM_URL}
RUN mkdir build
WORKDIR /home/ubuntu/work/build
RUN cmake -G Ninja /home/ubuntu/work/llvm-project/llvm \
    -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_ENABLE_PROJECTS="bolt"
RUN ninja bolt && ninja merge-fdata

WORKDIR /home/${USERNAME}
RUN sudo -E apt-get update && sudo -E apt-get upgrade -y && sudo -E apt-get install -y linux-tools-`uname -r`
COPY --chown=${USERNAME}:root start.sh /home/${USERNAME}/start.sh
```

Please be noted the ghost workload needs DB to be prepared ahead of time. As in the user manual document in ghost folder, you need to fill in some data in the DB.
You need to copy the `ghost.dump` and put the file into `genererate_bolt/common` folder.