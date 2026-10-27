#!/usr/bin/env bash

# Stop the ida-mcp HTTP server started by this Skill.
#
# Only a process whose command line contains ida-mcp, http and the configured
# port is touched; unrelated listeners on the port are never killed.
#
# Exit codes:
#   0  stopped, or already not running
#   1  the process did not stop within the timeout

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: stop-idamcp-http.sh

Stops the ida-mcp HTTP server on port ${HTTP_PORT}.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        err "unknown argument: $1"
        usage >&2
        exit 1
        ;;
esac

pid="$(read_pid || true)"
if [[ -n "${pid}" ]] && pid_alive "${pid}" && pid_is_idamcp_http "${pid}"; then
    :
else
    rm -f "${PID_FILE}"
    pid=""
    if have ss; then
        candidate="$(find_pid_by_port || true)"
        if [[ -n "${candidate}" ]] && pid_is_idamcp_http "${candidate}"; then
            pid="${candidate}"
        fi
    fi
fi

if [[ -z "${pid}" ]]; then
    log "ida-mcp HTTP 服务未运行"
    exit 0
fi

log "停止 ida-mcp HTTP 服务（PID ${pid}）"
kill "${pid}"

for _ in {1..20}; do
    if ! pid_alive "${pid}"; then
        rm -f "${PID_FILE}"
        log "已停止"
        exit 0
    fi
    sleep 0.5
done

err "服务未在 10 秒内退出（PID ${pid}）"
exit 1
