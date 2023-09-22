This is the user guide to download Ghost workload from public repo, and build the https working mode. It also downloads the ab tools as the client, and install the necessary DB as required by ghost official website.

```
ARG BASIC_IMAGE="node:latest"
FROM ${BASIC_IMAGE}

ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"
# RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone


RUN apt-get update && \
    apt --fix-broken install -y && \
    apt-get upgrade -y && \
    apt-get install -y build-essential git curl sudo \
    ca-certificates cmake ssh wget vim nano openssl libssl-dev \
    autoconf automake libpcre3-dev libexpat1 libexpat1-dev \
    gcc-10 g++-10 cpp-10 && \
    apt-get remove -y unattended-upgrades
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10

RUN mkdir /apache/ && \
    cd /apache/ && \
    curl -OkL http://archive.apache.org/dist/httpd/httpd-2.4.57.tar.gz && \
    tar zxvf httpd-2.4.57.tar.gz && \
    cd httpd-2.4.57 && \
    cd srclib && \
    curl -OkL https://archive.apache.org/dist/apr/apr-1.7.4.tar.gz && \
    curl -OkL https://archive.apache.org/dist/apr/apr-util-1.6.3.tar.gz && \
    tar zxvf apr-1.7.4.tar.gz && \
    mv apr-1.7.4/ apr/ && \
    tar zxvf apr-util-1.6.3.tar.gz && \
    mv apr-util-1.6.3/ apr-util/ && \
    cd .. && \
    ./configure && \
    make -j


ENV USERNAME="ghost"

ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
# Install required packages that are not included in ubuntu core image
RUN apt-get update && apt --fix-broken install -y && apt-get upgrade -y && apt-get install -y \
    mysql-server \
    sysstat \
    sudo \
    apache2-utils \
    nginx \
    openssl && \
    rm -rf /var/lib/apt/lists/*

# Copy patched ab binary and overwrite default one
RUN cp /apache/httpd-2.4.57/support/.libs/ab /usr/bin/ab

# Create new Linux account
RUN useradd -rm -d /home/${USERNAME} -s /bin/bash -g root -G sudo -u 1001 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Switch to ${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Upload ghost.dump database
COPY common/ghost.dump /home/${USERNAME}

# Configure mariadb and install ghost database
RUN echo "soft nofile 65536\nhard nofile 65536" | sudo tee -a /etc/security/limits.conf
RUN echo "\n[mysqld]\nopen_files_limit = 65536\nmax_connections = 10240" | sudo tee -a /etc/mysql/my.cnf

COPY common/setup_db.sh /tmp/setup_db.sh
RUN sudo chmod 777 /tmp/setup_db.sh && /tmp/setup_db.sh

# Download node v12.22.1 which is needed to install ghost, but will be removed afterwards
RUN wget https://nodejs.org/download/release/v12.22.1/node-v12.22.1-linux-x64.tar.xz

# Untar node v12.22.1
RUN tar xf node-v12.22.1-linux-x64.tar.xz
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
RUN /home/${USERNAME}/ghost-cli/node_modules/.bin/ghost install 4.40.0 local
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
COPY --chown=${USERNAME}:root common/nginx.conf.https  /home/${USERNAME}/nginx/nginx.conf
RUN mkdir /home/${USERNAME}/certificates
WORKDIR /home/${USERNAME}/certificates
RUN openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -keyout ./server.key -out ./server.crt -subj "/C=US/ST=OR/L=IN/O=IN/OU=IN/CN=$(hostname)"
RUN chown -R ${USERNAME}:root /home/${USERNAME}/certificates

WORKDIR /home/${USERNAME}

# Install perf tools
RUN sudo -E apt-get update && sudo -E apt-get install -y flex bison python2 linux-tools-`uname -r`
ARG perf_version="linux-6.2"

# Download and build linux tools, remaining perf-archive
RUN wget https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/${perf_version}.tar.xz && \
    tar xf ${perf_version}.tar.xz && \
    cd ${perf_version}/tools/perf && make CC=gcc ARCH=x86_64 && \
    cp perf-archive /home/${USERNAME}/Ghost/perf-archive && \
    rm -rf ${perf_version} ${perf_version}.tar.xz

# Clone FlameGraph and breakdown.sh
ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}
COPY --chown=${USERNAME}:root common/breakdown.sh /home/${USERNAME}/Ghost/breakdown.sh
COPY --chown=${USERNAME}:root common/perf_module_breakdown.py /home/${USERNAME}/Ghost/perf_module_breakdown.py

WORKDIR /home/${USERNAME}/Ghost

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [ "bash" ]
```