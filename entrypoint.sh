#!/usr/bin/env bash

set -euo pipefail

/generate-ipsec-config.sh

exec "${@}"
