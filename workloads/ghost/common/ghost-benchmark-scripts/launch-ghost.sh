#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT


# $1 count
# $2 starting port
# $3 where to store pids
# $4 prefix
# $5 Ghost.js root (directory containing current/ and config files).
# $6 Ghost.js version to run (versions/???).
# $7 scripts directory (for hack.js).
# $the_rest command

COUNT=$1
COUNT=${COUNT:-1}
shift
START_PORT=$1
START_PORT=${START_PORT:-2368}
shift
WHERE="$1"
shift
PREFIX="$1"
shift
GHOST_ROOT="$1"
shift
GHOST_VERSION="$1"
shift
SCRIPTS_DIRECTORY="$1"
shift
COMMAND="$@"
COMMAND=${COMMAND:-node}

# $1 JSON config file
# $2 port
# $3 logging path - set to stdout if empty
function set_server_config() {
  local CONF_FILE="$1"
  local PORT=$2
  local LOG_DIR="$3"
  local CONF_DIR="$(dirname "${CONF_FILE}")"
  local THIS_CONF_FILE="$(mktemp "${CONF_DIR}"/config.XXXXXX.json)"
  local SLUG="$(echo "${THIS_CONF_FILE}" | sed -r 's/^.*config[.]([^.]*).json$/\1/')"
  cp "${CONF_FILE}" "${THIS_CONF_FILE}"
  node -e "
    const cf = require('${THIS_CONF_FILE}');
    cf.server.port = ${PORT};
    if ('${LOG_DIR}' === '') {
      delete cf.logging.path;
      cf.logging.transports = ['stdout'];
    } else {
      cf.logging.path = '${LOG_DIR}';
      cf.logging.transports = ['file'];
    }
    require('fs').writeFileSync('${THIS_CONF_FILE}', JSON.stringify(cf, null, 4));
  "
  echo "${SLUG}"
}

# $1: Index
function launch_one() {
  local PORT=$[${START_PORT} + $1]
  local LOG_DIR="${WHERE}/${PREFIX}.$(printf "%03d" $1)"
  mkdir -p "${LOG_DIR}"
  local CONF_SLUG=$(set_server_config "${GHOST_ROOT}"/config.production.json "${PORT}" "${LOG_DIR}")
  bash -c "NODE_ENV=production NODE_REAL_ENV=\"${CONF_SLUG}\" ${COMMAND} -r \"${SCRIPTS_DIRECTORY}\"/hack.js \"${GHOST_ROOT}/versions/${GHOST_VERSION}/index.js\"" &
  local PID=$!
  # Try to avoid some of the "Server is starting up" errors by giving it some time to start up.
  sleep 2
  for ((wait = 0; wait < 180; wait++)); do
    wget --tries=1 --no-proxy -O /dev/null http://localhost:${PORT}/ 2>&1 | grep 'awaiting response... 200 OK' && break
    sleep 1
  done
  echo "${PID} ${GHOST_ROOT}/config.${CONF_SLUG}.json" > "$(mktemp "${WHERE}/XXXXXX.pid")"
}

echo "Launching test Node.js process..."
if ! bash -c "${COMMAND} -e 42"; then
  exit 1
fi

rm -f "${WHERE}/*.pid"
for ((Nix = 0; Nix < ${COUNT}; Nix++)); do
  launch_one ${Nix} &
done
wait
echo "Processes launched"
