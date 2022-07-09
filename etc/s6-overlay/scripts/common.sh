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
