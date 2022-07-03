#!/usr/bin/env bash

set -euo pipefail

/configure-strongswan.sh
/configure-ipsec.sh
/generate-ha-config.sh

exit_code=0
"${@}" &
server_pid=$!

wait_for_server() {
  echo "Waiting for server to finish." >&2
  wait "${server_pid}" || exit_code=$?
  exit "${exit_code}"
}

graceful_shutdown() {
  signal="${1}"
  echo "Received ${signal}, shutting down." >&2
  kill -s "${signal}" "${server_pid}"
  wait_for_server
}

trap 'graceful_shutdown SIGINT' INT
trap 'graceful_shutdown SIGTERM' TERM

while kill -0 "${server_pid}"; do
  /ha-loop.sh "${server_pid}"
done

wait_for_server
