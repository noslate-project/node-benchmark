ARG BASIC_IMAGE=
FROM ${BASIC_IMAGE}

WORKDIR /home
COPY ./scripts/start.sh ./start.sh

RUN apt update && apt upgrade -y && apt install -y python2 linux-tools-`uname -r` wget

ARG FlameGraph_URL="https://github.com/brendangregg/FlameGraph.git"
RUN git clone --depth 1 --branch master ${FlameGraph_URL}

COPY ./scripts/breakdown.sh /home/breakdown.sh
COPY ./scripts/perf_module_breakdown.py /home/perf_module_breakdown.py
COPY ./scripts/buffer /home/ubuntu/work/buffer
COPY ./scripts/_http-benchmarkers.js /home/ubuntu/work/_http-benchmarkers.js
COPY ./scripts/common.js /home/ubuntu/work/common.js
COPY ./scripts/perf_module_breakdown.py /home/perf_module_breakdown.py

RUN npm install -g npm
