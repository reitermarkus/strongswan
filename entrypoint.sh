#!/usr/bin/env bash

set -euo pipefail

/configure-strongswan.sh
/configure-ipsec.sh

"${@}" &
server_pid=$!

wait_for_server() {
  wait "${server_pid}" || exit_code=$?
  exit "${exit_code}"
}

graceful_shutdown() {
  signal="${1}"
  echo "Received ${signal}, shutting down."
  /graceful-shutdown || kill "${server_pid}"
  wait_for_server
}

trap 'graceful_shutdown SIGINT' INT
trap 'graceful_shutdown SIGTERM' TERM

/ha-setup.sh

wait "${server_pid}"
