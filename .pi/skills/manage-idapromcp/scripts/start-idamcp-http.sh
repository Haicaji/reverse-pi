#!/usr/bin/env bash

# Start the ida-mcp HTTP MCP server as a background process.
#
# Exit codes:
#   0  server running and MCP initialize succeeded
#   10 ida-mcp is not installed in the selected Python environment
#   12 ss/curl is missing, or the Python interpreter is unusable
#   1  port conflict or startup failure

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: start-idamcp-http.sh

Starts the ida-mcp HTTP MCP server in the background.

Defaults:
  host          ${DEFAULT_HTTP_HOST}
  port          ${DEFAULT_HTTP_PORT}
  state         ${STATE_DIR}
  MCP endpoint  ${MCP_URL}

Environment overrides:
  IDA_MCP_PYTHON     Python environment containing ida-mcp (default: python3)
  IDA_MCP_HTTP_HOST  Bind address (default: ${DEFAULT_HTTP_HOST})
  IDA_MCP_HTTP_PORT  Port (default: ${DEFAULT_HTTP_PORT})
  IDA_MCP_STATE_DIR  PID directory (default: ${STATE_DIR})
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

if ! have "${IDA_MCP_PYTHON}"; then
    err "Python 解释器不可用：${IDA_MCP_PYTHON}"
    exit 12
fi

if ! python_supported; then
    err "需要 Python ${IDA_MCP_MIN_PYTHON}+，当前：$(python_version || echo unknown)"
    exit 12
fi

if ! version="$(idamcp_version)"; then
    err "ida-mcp 未安装于 ${IDA_MCP_PYTHON}"
    log "安装：${script_dir}/install-idamcp.sh"
    exit 10
fi

command_path="$(idamcp_command || true)"
if [[ -z "${command_path}" ]]; then
    err "未找到 ida-mcp 入口命令"
    exit 10
fi

existing_pid="$(read_pid || true)"
if [[ -n "${existing_pid}" ]] && pid_alive "${existing_pid}" && pid_is_idamcp_http "${existing_pid}"; then
    log "ida-mcp HTTP 服务已在运行（PID ${existing_pid}，版本 ${version}）"
    if wait_for_mcp 5; then
        log "MCP 就绪：${MCP_URL}"
        exit 0
    fi
    err "进程存在但 MCP 无响应；可先停止再重新启动"
    exit 1
fi

if [[ -n "${existing_pid}" ]]; then
    rm -f "${PID_FILE}"
fi

if port_in_use; then
    owner="$(find_pid_by_port || true)"
    if [[ -n "${owner}" ]] && pid_is_idamcp_http "${owner}"; then
        printf '%s\n' "${owner}" >"${PID_FILE}"
        log "接管已运行的 ida-mcp HTTP 服务（PID ${owner}）"
        if wait_for_mcp 5; then
            log "MCP 就绪：${MCP_URL}"
            exit 0
        fi
        err "服务无响应；可先停止再重新启动"
        exit 1
    fi

    err "端口 ${HTTP_PORT} 已被其他进程占用，本 Skill 不会结束该进程"
    if [[ -n "${owner}" ]]; then
        log "占用进程 PID ${owner}：$(tr '\0' ' ' <"/proc/${owner}/cmdline" 2>/dev/null || true)"
    fi
    log "可用 IDA_MCP_HTTP_PORT 指定其他端口后重试"
    exit 1
fi

mkdir -p "${STATE_DIR}"
chmod 700 "${STATE_DIR}"
rm -f "${PID_FILE}"

log "启动 ida-mcp HTTP 服务：${HTTP_HOST}:${HTTP_PORT}（版本 ${version}）"
nohup "${command_path}" http --host "${HTTP_HOST}" --port "${HTTP_PORT}" \
    >/dev/null 2>&1 </dev/null &
pid=$!
printf '%s\n' "${pid}" >"${PID_FILE}"

if ! wait_for_mcp 30; then
    err "启动失败或 MCP 未在 30 秒内就绪"
    if pid_alive "${pid}"; then
        kill "${pid}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
    exit 1
fi

log "MCP 就绪：${MCP_URL}（PID ${pid}）"
log "PID 文件：${PID_FILE}"
exit 0
