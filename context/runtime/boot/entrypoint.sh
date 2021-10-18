#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)"
readonly root
# shellcheck source=/dev/null
source "$root/helpers.sh"
# shellcheck source=/dev/null
source "$root/mdns.sh"

helpers::dir::writable "/certs"
helpers::dir::writable "/data"
helpers::dir::writable "/tmp"
helpers::dir::writable "$XDG_RUNTIME_DIR" create
helpers::dir::writable "$XDG_STATE_HOME" create
helpers::dir::writable "$XDG_CACHE_HOME" create

# mDNS blast if asked to
[ ! "$MDNS_HOST" ] || {
  _mdns_port="$([ "$TLS" != "" ] && printf "%s" "${PORT_HTTPS:-443}" || printf "%s" "${PORT_HTTP:-80}")"
  [ ! "${MDNS_STATION:-}" ] || mdns::add "_workstation._tcp" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::add "${MDNS_TYPE:-_http._tcp}" "$MDNS_HOST" "${MDNS_NAME:-}" "$_mdns_port"
  mdns::start &
}

# Start the sidecar
start::sidecar &

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
