# Usage: FROM [image name]
ARG BASIC_IMAGE=
FROM ${BASIC_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"
LABEL authors="lei.a.shi@intel.com"

ENV USERNAME="faas"

# Install required packages that are not included in ubuntu core image
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    wget \
    vim \
    sysstat \
    htop \
    sudo && \
    rm -rf /var/lib/apt/lists/*

# Create new Linux account
RUN useradd -rm -d /home/${USERNAME} -s /bin/bash -g root -G sudo -u 1001 ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" | tee -a /etc/sudoers

# Switch to ${USERNAME}
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Install Ali FaaS start up micro bench
COPY --chown=${USERNAME}:root ./common/index.allcache.js /home/${USERNAME}
COPY --chown=${USERNAME}:root ./common/package.json /home/${USERNAME}/
COPY --chown=${USERNAME}:root ./common/quickrun_allcache.sh /home/${USERNAME}/quickrun.sh
COPY --chown=${USERNAME}:root ./common/allcache.js /home/${USERNAME}/

RUN npm install
