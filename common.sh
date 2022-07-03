#!/usr/bin/env bash

conf_set() {
  local file="${1}"
  local key="${2}"
  local value="${3-\4}"

  sed -i -E "s/(\\s+)(#\\s*)?(${key})\\s*=\\s*(.*)/\\1\\3 = ${value}/" "${file}"
}

conf_get() {
  local file="${1}"
  local key="${2}"

  grep -E "^\\s+${key}\\s*=" "${file}" | sed -E 's/.*=\s*//'
}

ha_conf_set() {
  conf_set /etc/strongswan.d/charon/ha.conf "${@}"
}

ha_conf_get() {
  local key="${1}"
  grep -E "^\\s+${key}\\s*=" /etc/strongswan.d/charon/ha.conf | sed -E 's/.*=\s*//'
}

# Get all IP addresses for the headless service, except our own.
ha_remote_addresses() {
  nslookup "${HEADLESS_SERVICE}" | awk "/${HEADLESS_SERVICE}/ { f = 1; next } f && /Address:\s+(\d+\.\d+\.\d+\.\d+)/ { print \$2 } f = 0" \
    | awk "/^${POD_IP}$/ { next } { print }"
}
