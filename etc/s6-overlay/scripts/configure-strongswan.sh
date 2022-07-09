#!/command/with-contenv bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${0}")"
# shellcheck source=etc/s6-overlay/scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

STRONGSWAN_DIR=/etc/strongswan.d
CHARON_DIR="${STRONGSWAN_DIR}/charon"

# Disable Bypass LAN to allow LAN access.
conf_set "${CHARON_DIR}/bypass-lan.conf" load no
