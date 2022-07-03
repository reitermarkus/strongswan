#!/usr/bin/env bash

set -euo pipefail

. /common.sh

ha_conf_set autobalance
ha_conf_set fifo_interface
ha_conf_set heartbeat_delay
ha_conf_set heartbeat_timeout
ha_conf_set monitor
ha_conf_set resync
ha_conf_set segment_count

if [[ -z "${POD_IP-}" ]] && [[ -z "${HEADLESS_SERVICE-}" ]]; then
  exit
fi

ha_conf_set local "${POD_IP}"

if [[ -n "${HA_SECRET-}" ]]; then
  ha_conf_set secret "${HA_SECRET}"
fi


echo "Checking for HA remotes."
if remote_ip="$(select_remote)"; then
  echo "Setting high availability remote to '${remote_ip}'."
  ha_conf_set remote "${remote_ip}"
else
  echo "Warning: Starting without high availability." >&2
fi
