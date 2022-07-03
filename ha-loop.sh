#!/usr/bin/env bash

set -euo pipefail

. /common.sh

server_pid="${1}"

if [[ -z "${POD_IP-}" ]]; then
  exit
fi

update_remote() {
  local remote_ip="${1}"

  local current_remote_ip
  current_remote_ip="$(ha_conf_get remote)"

  if [[ "${remote_ip}" != "${current_remote_ip}" ]]; then
    echo "Updating high availability remote to '${remote_ip}'."
    ha_conf_set remote "${remote_ip}"

    sed -i -E "s/#\s+(remote\s+=).*/\1 ${1}/" /etc/strongswan.d/charon/ha.conf
    kill -HUP "${server_pid}"
  fi
}

if remote_ip="$(ha_remote_addresses | head -n 1)"; then
  update_remote "${remote_ip}"
fi
