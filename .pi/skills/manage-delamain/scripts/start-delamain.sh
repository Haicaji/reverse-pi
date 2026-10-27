#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
# shellcheck source=config.sh
source "${script_dir}/config.sh"

docker_ok || exit $?
require_installed || exit $?

if port_in_use && ! our_container_running; then
    echo "DELAMAIN_PORT_IN_USE: port ${PORT} is owned by another process." >&2
    ss -ltnp 2>/dev/null | grep -E "[:.]${PORT}[[:space:]]" >&2 || true
    exit 1
fi

log "starting ${CONTAINER_NAME} on 127.0.0.1:${PORT}"
compose up -d

log "waiting for /health (up to 180s)"
if ! health_json="$(wait_for_health 180)"; then
    echo "DELAMAIN_HEALTH_TIMEOUT: /health did not become healthy." >&2
    compose ps >&2 || true
    compose logs --tail=100 >&2 || true
    exit 1
fi

printf 'delamain is ready: %s\n' "${MCP_URL}"
printf 'health: %s\n' "$(printf '%s' "${health_json}" | jq -c . 2>/dev/null || printf '%s' "${health_json}")"
