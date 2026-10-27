#!/usr/bin/env bash

# Check whether the ida-mcp HTTP server is running and callable.
#
# Exit codes:
#   0  server running and MCP initialize succeeded
#   1  server not running, or MCP not responding
#   12 ss/curl is missing

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: check-idamcp-http.sh

Checks the ida-mcp HTTP server on ${MCP_URL}.
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

require_http_tools

pid="$(read_pid || true)"
if [[ -z "${pid}" ]] || ! pid_alive "${pid}" || ! pid_is_idamcp_http "${pid}"; then
    pid=""
    if port_in_use; then
        owner="$(find_pid_by_port || true)"
        if [[ -n "${owner}" ]] && pid_is_idamcp_http "${owner}"; then
            pid="${owner}"
        else
            err "端口 ${HTTP_PORT} 被其他进程占用"
            if [[ -n "${owner}" ]]; then
                log "占用进程 PID ${owner}：$(tr '\0' ' ' <"/proc/${owner}/cmdline" 2>/dev/null || true)"
            fi
            exit 1
        fi
    fi
fi

if [[ -z "${pid}" ]]; then
    log "ida-mcp HTTP 服务未运行（${MCP_URL}）"
    log "启动：${script_dir}/start-idamcp-http.sh"
    exit 1
fi

version="$(idamcp_version || true)"
log "进程运行中：PID ${pid}${version:+，ida-mcp ${version}}"

if wait_for_mcp 3; then
    log "MCP 就绪：${MCP_URL}"
    exit 0
fi

err "MCP 无响应：${MCP_URL}"
log "可执行 ${script_dir}/stop-idamcp-http.sh 后重新启动"
exit 1
