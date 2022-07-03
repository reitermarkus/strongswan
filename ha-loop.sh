#!/usr/bin/env bash

set -euo pipefail

. /common.sh

server_pid="${1}"

if [[ -z "${POD_IP-}" ]]; then
  exit
fi

mapfile -t remote_ips < <(ha_remote_addresses)

if [[ ${#remote_ips[@]} -ge 1 ]]; then
  remote_ip="${remote_ips[0]}"
  current_remote_ip="$(ha_conf_get remote)"

  if [[ "${remote_ip}" != "${current_remote_ip}" ]]; then
    if [[ ${#remote_ips[@]} -ge 2 ]]; then
      echo "Warning: Multiple remotes found (${remote_ips}), choosing first."
    fi

    echo "Updating high availability remote to '${remote_ip}'."
    ha_conf_set remote "${remote_ip}"
    kill -HUP "${server_pid}"
  fi
fi

heartbeat_delay="$(ha_conf_get heartbeat_delay)"
sleep "${heartbeat_delay}e-3"
