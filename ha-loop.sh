#!/usr/bin/env bash

set -euo pipefail

. /common.sh

server_pid="${1}"

switch_remote_if_needed() {
  local current_remote_ip
  if current_remote_ip="$(ha_conf_get remote)"; then
    if is_remote_reachable "${current_remote_ip}"; then
      echo "Current remote is still reachable." >&2
      return 0
    else
      echo "Current remote is not reachable anymore, checking for new remote." >&2
    fi
  else
    echo "No remote is currently set, checking for new remote."
  fi

  if remote_ip="$(select_remote)"; then
    if [[ "${remote_ip}" != "${current_remote_ip}" ]]; then
      echo "Updating high availability remote to '${remote_ip}'." >&2
      ha_conf_set remote "${remote_ip}"
      swanctl --reload-settings
    fi
  fi
}

if [[ -n "${POD_IP-}" ]] || [[ -n "${HEADLESS_SERVICE-}" ]]; then
  switch_remote_if_needed
fi

heartbeat_delay="$(ha_conf_get heartbeat_delay)"
sleep "$(( (heartbeat_delay + 999) / 1000 ))"
