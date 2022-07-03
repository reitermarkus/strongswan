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
  conf_get /etc/strongswan.d/charon/ha.conf "${@}"
}

# Get all IP addresses for the headless service, except our own.
ha_remote_addresses() {
  nslookup "${HEADLESS_SERVICE}" | awk "/${HEADLESS_SERVICE}/ { f = 1; next } f && /Address:\s+(\d+\.\d+\.\d+\.\d+)/ { print \$2 } f = 0" \
    | awk "/^${POD_IP}$/ { next } { print }"
}

is_debug() {
  [[ "${DEBUG-}" == 'true' ]]
}

is_remote_reachable() {
  local remote_ip="${1}"

  local verbose_args=( )
  if is_debug; then
    verbose_args=( -v )
  fi

  nc -uz "${verbose_args[@]}" "${remote_ip}" 4510 >&2
}

select_reachable_remote() {
  local remote_ip
  for remote_ip in "${@}"; do
    if is_remote_reachable "${remote_ip}"; then
      echo "Remote '${remote_ip}' is in high availability mode." >&2
      echo "${remote_ip}"
      return 0
    else
      echo "Remote '${remote_ip}' is not in high availability mode." >&2
    fi
  done

  return 1
}

select_remote() {
  local remote_ip
  local remote_ips
  mapfile -t remote_ips < <(ha_remote_addresses)

  if [[ ${#remote_ips[@]} -eq 0 ]]; then
    echo 'No remote found.' >&2
    return 1
  elif [[ ${#remote_ips[@]} -eq 1 ]]; then
    remote_ip="${remote_ips[0]}"
    echo "Found remote '${remote_ip}'." >&2
  else
    local reachable_remote_ip
    if reachable_remote_ip="$(select_reachable_remote "${remote_ips[@]}")"; then
      remote_ip="${reachable_remote_ip}"
      echo "Found multiple remotes, selecting first in high availability mode, remote '${remote_ip}'." >&2
    else
      remote_ip"${remote_ips[0]}"
      echo "Found multiple remotes but none in high availability mode, falling back to first remote '${remote_ip}'." >&2
    fi
  fi

  echo "${remote_ip}"
}
