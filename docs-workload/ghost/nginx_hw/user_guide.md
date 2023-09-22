This is the user guide to download Ghost workload from public repo, and build the https working mode with Async Ngnix web server to do load balance and https request decryption. 

Please download and compile QAT lib on the host, package it as qat.tar.gz, and place it in the following directory. Then compile the nginx_hw image.
```sh
nginx_hw/
├── files
│   └── qat.tar.gz
└── user_guide.md
```

```

ARG BASIC_IMAGE=

####################################################################
#                Developing container image                        #
#    Prepare optimized Node binary for 'ghost.js' workload         #
####################################################################
FROM ubuntu:22.04 as build
LABEL maintainer="chenyu.yang@intel.com"

ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"

# RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN mkdir -p /opt/intel/
ADD nginx_hw/files/qat.tar.gz /opt/intel/

RUN apt-get update && \
    apt-get install -y build-essential git curl sudo pkg-config \
    ca-certificates cmake ssh wget vim nano openssl libssl-dev \
    autoconf automake libpcre3-dev libexpat1 libexpat1-dev \
    gcc-10 g++-10 cpp-10 && \
    apt-get remove -y unattended-upgrades
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
    --slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10

RUN cd /apache/ && \
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

# For async nginx building(Intel-specific
RUN apt-get update && \
    apt-get install -y cpuid libtool libpcre3 libpcre3-dev zlib1g zlib1g-dev libssl-dev nasm && \
    apt-get remove -y unattended-upgrades

ARG OPENSSL_RELEASE="OpenSSL_1_1_1j"
RUN git clone -b $OPENSSL_RELEASE https://github.com/openssl/openssl.git
RUN cd ./openssl && \
    ./config && \
    make depend && \
    make && \
    make install_sw

ARG QAT_ENGINE_VERSION="v1.0.0"
RUN git clone -b $QAT_ENGINE_VERSION https://github.com/intel/QAT_Engine.git && \
    cd ./QAT_Engine && \
    ./autogen.sh && \
    ./configure \
        --enable-upstream_driver \
        --with-qat_hw_dir=/opt/intel/QAT && \ 
    make && \
    make install

ENV ICP_ROOT="/opt/intel/QAT"
ARG ASYNC_NGINX_VERSION="v0.5.0"
RUN git clone -b $ASYNC_NGINX_VERSION https://github.com/intel/asynch_mode_nginx.git && \
    cd ./asynch_mode_nginx && \
    ./configure \
      --prefix=/var/www \
      --conf-path=/usr/local/share/nginx/conf/nginx.conf \
      --sbin-path=/usr/local/bin/nginx \
      --pid-path=/run/nginx.pid \
      --lock-path=/run/lock/nginx.lock \
      --modules-path=/var/www/modules/ \
      --without-http_rewrite_module \
      --with-http_ssl_module \
      --with-pcre \
      --add-dynamic-module=modules/nginx_qat_module/ \
      --with-cc-opt="-DNGX_SECURE_MEM -I$ICP_ROOT/quickassist/include -I$ICP_ROOT/quickassist/include/dc  -I/usr/local/include/openssl -Wno-error=deprecated-declarations -Wimplicit-fallthrough=0" \
      --with-ld-opt="-Wl,-rpath=/usr/local/lib -L/usr/local/lib -L/usr/local/lib" \
      --user=root \
      --group=root && \
    make && \
    make install

####################################################################
#                Production container image                        #
#    Integrate patched ab binary into ghost.js workload            #
####################################################################
FROM ${BASIC_IMAGE}
LABEL authors="chenyu.yang@intel.com"
ENV USERNAME="ghost"

ARG DEBIAN_FRONTEND="noninteractive"
ARG TZ="America/Los_Angeles"
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1

# Install required packages that are not included in ubuntu core image
RUN apt-get update && apt-get install -y \
    mysql-server curl build-essential wrk pkg-config\
    sysstat \
    sudo \
    apache2-utils \
    nginx \
    wget \
    openssl && \
    rm -rf /var/lib/apt/lists/*

# Copy patched ab binary and overwrite default one
COPY --from=build /apache/httpd-2.4.57/support/.libs/ab /usr/bin/ab

COPY --from=build /usr/local/ /usr/local/
COPY --from=build /var/www/ /var/www/
RUN mkdir -p /opt/intel/
COPY --from=build /opt/intel/QAT /opt/intel/QAT
COPY --from=build /opt/intel/QAT/build/libqat_s.so /usr/local/lib/engines-1.1/

ENV OPENSSL_ENGINES=/usr/local/lib/engines-1.1
RUN ldconfig
RUN /bin/bash -c 'mkdir -p /usr/local/ssl/;cp /etc/ssl/openssl.cnf /usr/local/ssl/'

# Create new Linux account
RUN useradd -rm -d /home/${USERNAME} -s /bin/bash -g root -G sudo -u 1001 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers
RUN chown -R ${USERNAME}:root /usr/local/share/nginx/ && \
    chown -R ${USERNAME}:root /var/www/

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
RUN wget https://nodejs.org/download/release/v12.22.1/node-v12.22.1-linux-x64.tar.xz --no-check-certificate

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
COPY --chown=${USERNAME}:root common/nginx.conf.qat-hw /home/${USERNAME}/nginx/nginx.conf
RUN mkdir /home/${USERNAME}/certificates
WORKDIR /home/${USERNAME}/certificates
RUN openssl req -newkey rsa:2048 -nodes -keyout ./rsa.key -x509 -days 365 -out ./rsa.crt -subj "/C=US/ST=OR/L=IN/O=IN/OU=IN/CN=$(hostname)"
#For DSA encryption later
#RUN openssl ecparam -genkey -out /usr/local/share/nginx/certs/dsa.key -name prime256v1
#RUN openssl req -x509 -new -key /usr/local/share/nginx/certs/dsa.key -out /usr/local/share/nginx/certs/dsa.crt -subj "/C=/ST=/L=/O=/OU=/CN=$(hostname)"
RUN chown -R ${USERNAME}:root /home/${USERNAME}/certificates

WORKDIR /home/${USERNAME}/Ghost

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD [ "bash" ]
```