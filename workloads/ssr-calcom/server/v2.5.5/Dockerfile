ARG BASIC_IMAGE="node:latest"
FROM ${BASIC_IMAGE} as node-stage
RUN cp -r /usr/local /home/

# Copy Node Binary into ubuntu:22.04
# Here exists bugs in ubuntu:20.04
FROM ubuntu:22.04
COPY --from=node-stage /usr/local /usr/local

ENV TZ=Etc/UTC
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /calcom

# install postgres for install calcom
RUN apt-get update && \
    apt-get install -y sudo lsb-release wget build-essential git && \
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - && \
    apt-get update && \
    apt-get -y install postgresql-15
RUN npm install -g yarn@1.22.19

# Install Cal.com
ARG CALCOM_URL="https://github.com/calcom/cal.com.git"
ARG CALCOM_VERSION="v2.5.5"
RUN git clone --depth 1 --branch ${CALCOM_VERSION} ${CALCOM_URL}

# COPY scripts/.env ./cal.com
COPY scripts/* ./cal.com/
RUN cd cal.com && ./modify.sh

WORKDIR /calcom/cal.com
RUN ./startdb.sh && \ 
    yarn config set network-timeout 1000000000 -g && \
    yarn && \
    yarn workspace @calcom/prisma db-migrate && \
    yarn workspace @calcom/prisma db-deploy && \
    yarn build

# Clone FlameGraph and breakdown.sh
WORKDIR /calcom
ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}
RUN apt install -y python2 linux-tools-`uname -r`

WORKDIR /calcom/cal.com
EXPOSE 3000
EXPOSE 5432
