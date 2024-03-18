#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
. "$root/helpers.sh"
# shellcheck source=/dev/null
. "$root/mdns.sh"

helpers::dir::writable "/certs"
helpers::dir::writable "$XDG_DATA_HOME" create
helpers::dir::writable "$XDG_DATA_DIRS" create
helpers::dir::writable "$XDG_RUNTIME_DIR" create
helpers::dir::writable "$XDG_STATE_HOME" create
helpers::dir::writable "$XDG_CACHE_HOME" create

# HTTP helpers
if [ "$MOD_HTTP_ENABLED" == true ]; then
  case "${1:-}" in
    # Short hand helper to generate password hash
    "hash")
      shift
      http::hash "$@"
      exit
    ;;
    # Helper to get the ca.crt out (once initialized)
    "cert")
      shift
      http::certificate "${MOD_HTTP_TLS_MODE:-internal}" "$@"
      exit
    ;;
  esac
  http::start &
fi

[ "${MOD_MDNS_ENABLED:-}" != true ] || \
  mdns::start::default \
    "${MOD_MDNS_HOST:-}" \
    "${MOD_MDNS_NAME:-}" \
    "${MOD_HTTP_ENABLED:-}" \
    "${MOD_HTTP_TLS_ENABLED:-}" \
    "${MOD_TLS_ENABLED:-}" \
    "${ADVANCED_MOD_MDNS_STATION:-}" \
    "${ADVANCED_MOD_MDNS_TYPE:-}" \
    "${ADVANCED_MOD_HTTP_PORT:-}" \
    "${ADVANCED_MOD_HTTP_PORT_INSECURE:-}" \
    "${ADVANCED_MOD_TLS_PORT:-}"

# Get athens started

# Ensure the tmp go folder is here
helpers::dir::writable "/tmp/go" create

# Careful, it uses the PORT env variable to override its default, so blank it out
export PORT=""
# Forward log_level
export ATHENS_LOG_LEVEL=${LOG_LEVEL:-warn}
# Maybe this should be more flexible?
export ATHENS_INDEX_TYPE="memory"
# The rest is fine
export ATHENS_STORAGE_TYPE=disk
export ATHENS_PORT=":10042"
export ATHENS_DISK_STORAGE_ROOT=/data
export ATHENS_GOGOET_DIR=/tmp/go

exec athens-proxy -config_file /config/athens/main.toml "$@"
