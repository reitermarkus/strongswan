#!/usr/bin/env bash

set -euo pipefail

. /common.sh

if [[ -z "${POD_IP-}" ]]; then
  exit
fi

conf_set /etc/strongswan.d/charon.conf load_modular yes

ha_conf_set autobalance
ha_conf_set fifo_interface
ha_conf_set heartbeat_delay
ha_conf_set heartbeat_timeout
ha_conf_set local "${POD_IP}"
ha_conf_set monitor
ha_conf_set resync
ha_conf_set secret "${HA_SECRET}"
ha_conf_set segment_count

mapfile -t remote_ips < <(ha_remote_addresses)

if [[ ${#remote_ips[@]} -eq 0 ]]; then
  echo "Warning: No remote found, starting without high availability."
else
  remote_ip="${remote_ips[0]}"
  echo "Setting high availability remote to '${remote_ip}'."
  ha_conf_set remote "${remote_ip}"
fi
