#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
# shellcheck source=config.sh
source "${script_dir}/config.sh"

docker_ok || exit $?
require_installed || exit $?

if ! our_container_running; then
    log "${CONTAINER_NAME} is not running"
    exit 0
fi

log "stopping ${CONTAINER_NAME}"
compose stop
log "${CONTAINER_NAME} stopped (data and indices are preserved)"
