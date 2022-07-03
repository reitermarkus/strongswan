#!/usr/bin/env bash

server_pid="${1}"

set -euo pipefail

if [[ -z "${POD_IP-}" ]]; then
  exit
fi

local_ip="${POD_IP}"
secret="${HA_SECRET}"

# sed -i -E 's/#\s+(autobalance.*)/\1/' /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(fifo_interface.*)/\1/' /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(heartbeat_delay.*)/\1/' /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(heartbeat_timeout.*)/\1/' /etc/strongswan.d/charon/ha.conf
sed -i -E "s/#\s+(local\s+=).*/\1 ${local_ip}/" /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(monitor.*)/\1/' /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(resync.*)/\1/' /etc/strongswan.d/charon/ha.conf
sed -i -E "s/#\s+(secret\s+=).*/\1 ${secret}/" /etc/strongswan.d/charon/ha.conf
# sed -i -E 's/#\s+(segment_count.*)/\1/' /etc/strongswan.d/charon/ha.conf

# Get all IP addresses for the headless service.
service_addresses() {
  nslookup "${HEADLESS_SERVICE}" | awk "/${HEADLESS_SERVICE}/ { f = 1; next } f && /Address:\s+(\d+\.\d+\.\d+\.\d+)/ { print \$2 } f = 0"
}

filter_self() {
  awk "/^${local_ip}$/ { next } { print }"
}

peer_addresses() {
  service_addresses | filter_self
}



update_remote() {
  sed -i -E "s/#\s+(remote\s+=).*/\1 ${1}/" /etc/strongswan.d/charon/ha.conf
  kill -HUP "${server_pid}"
}

if remote_ip="$(peer_addresses | head -n 1)"; then
  update_remote "${remote_ip}"
fi

while kill -0 "${server_pid}"; do
  for peer_address in $(peer_addresses); do
    nmap -sU "${peer_address}" -p 4510
  done || true
done
