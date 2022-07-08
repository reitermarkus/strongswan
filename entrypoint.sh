#!/usr/bin/env bash

set -euo pipefail

/configure-strongswan.sh
/configure-ipsec.sh

exec "${@}"
