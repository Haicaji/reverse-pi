#!/usr/bin/env bash

# Detect ida-mcp in the selected Python environment.
#
# Exit codes:
#   0  ida-mcp is installed
#   10 ida-mcp is not installed
#   12 the Python interpreter is missing or older than the supported minimum

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: check-idamcp.sh

Checks whether ida-mcp is installed in the selected Python environment.

Python selection:
  IDA_MCP_PYTHON=${IDA_MCP_PYTHON}   (override with the environment variable)

Minimum Python version: ${IDA_MCP_MIN_PYTHON}
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

if ! have "${IDA_MCP_PYTHON}"; then
    err "Python 解释器不可用：${IDA_MCP_PYTHON}"
    log "可通过 IDA_MCP_PYTHON 指定解释器，或使用 install-idamcp.sh --python。"
    exit 12
fi

python_path="$(python_executable || true)"
if [[ -z "${python_path}" ]]; then
    err "无法解析 Python 解释器：${IDA_MCP_PYTHON}"
    exit 12
fi

if ! python_supported; then
    err "需要 Python ${IDA_MCP_MIN_PYTHON}+，当前：$(python_version || echo unknown)（${python_path}）"
    exit 12
fi

version="$(idamcp_version || true)"
if [[ -z "${version}" ]]; then
    err "ida-mcp 未安装在 ${python_path}"
    log "安装：${script_dir}/install-idamcp.sh"
    exit 10
fi

log "ida-mcp ${version} 已安装"
log "Python：${python_path}"

command_path="$(idamcp_command || true)"
if [[ -n "${command_path}" ]]; then
    log "命令：${command_path}"
else
    warn "未找到 ida-mcp 入口脚本，Python 环境可能不完整"
fi

if "${IDA_MCP_PYTHON}" -c 'import ida_mcp' >/dev/null 2>&1; then
    log "模块：ida_mcp 可导入"
else
    warn "模块：ida_mcp 导入失败"
fi

exit 0
