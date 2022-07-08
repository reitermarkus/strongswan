#!/usr/bin/env bash

set -euo pipefail

. /common.sh

STRONGSWAN_DIR=/etc/strongswan.d
CHARON_DIR="${STRONGSWAN_DIR}/charon"

# Disable Bypass LAN to allow LAN access.
conf_set "${CHARON_DIR}/bypass-lan.conf" load no
