This is the user guide to download SSR workload and compose the Dockerfile for server side of v2.5.5 if you are using lower version of Node.js.

Please be noted that the version will be picked up automatically by the framework depending on the Node.js version in use.

``
# The basic os must be ubuntu:22.04
ARG BASIC_IMAGE="node:latest"
FROM ${BASIC_IMAGE}

ENV TZ=Etc/UTC
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /calcom

# install postgres for install calcom
RUN apt-get update && apt --fix-broken install -y && apt-get upgrade -y && \
    apt-get install -y sudo lsb-release wget build-essential git && \
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
    apt-get update && \
    apt-get -y install postgresql-15
RUN npm install -g yarn

# Install Cal.com
ARG CALCOM_URL="https://github.com/calcom/cal.com.git"
ARG CALCOM_VERSION="v2.9.6"
RUN git clone --depth 1 --branch ${CALCOM_VERSION} ${CALCOM_URL}

# COPY scripts/.env ./cal.com
COPY scripts/* ./cal.com/
RUN cd cal.com && ./modify.sh

WORKDIR /calcom/cal.com
ARG HTTP_PROXY=
ARG HTTPS_PROXY=
RUN ./startdb.sh && \
    ./set-proxy.sh ${HTTP_PROXY} ${HTTPS_PROXY} && \
    yarn && \
    yarn workspace @calcom/prisma db-migrate && \
    yarn workspace @calcom/prisma db-deploy && \
    npx prettier --write apps/web/components/PageWrapper.tsx && \
    yarn build

# Clone FlameGraph and breakdown.sh
WORKDIR /calcom
ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}
RUN apt install -y python2 linux-tools-`uname -r`

WORKDIR /calcom/cal.com
EXPOSE 3000
EXPOSE 5432

```

In this folder, we also provides some py and sh script to seamlessly run and profile this workload.