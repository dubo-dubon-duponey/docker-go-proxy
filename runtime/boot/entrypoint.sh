#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the certs folder is writable
[ -w "/tmp" ] || {
  >&2 printf "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

# Ensure the tmp go folder is here
mkdir -p /tmp/go
[ ! "$ATHENS_DISK_STORAGE_ROOT" ] || mkdir -p "$ATHENS_DISK_STORAGE_ROOT"

# Get athens started
exec athens-proxy -config_file /config/config.toml "$@"
