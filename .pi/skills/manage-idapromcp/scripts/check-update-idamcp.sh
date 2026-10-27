#!/usr/bin/env bash

# Compare the installed ida-mcp with the version declared on upstream main.
#
# ida-mcp is installed from the Git repository, so the reference point is the
# version in https://github.com/HexRaysSA/ida-mcp/blob/main/pyproject.toml.
#
# Exit codes:
#   0  up to date (or newer than upstream main)
#   20 update available
#   10 ida-mcp is not installed
#   12 the Python interpreter is missing or too old
#   1  the upstream version could not be queried

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: check-update-idamcp.sh

Compares the ida-mcp installed in the selected Python environment with the
version declared on the upstream main branch.

Python selection:
  IDA_MCP_PYTHON=${IDA_MCP_PYTHON}   (override with the environment variable)
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
    exit 12
fi

if ! python_supported; then
    err "需要 Python ${IDA_MCP_MIN_PYTHON}+，当前：$(python_version || echo unknown)"
    exit 12
fi

current_version="$(idamcp_version || true)"
if [[ -z "${current_version}" ]]; then
    err "ida-mcp 未安装在 $(python_executable || printf '%s' "${IDA_MCP_PYTHON}")"
    log "安装：${script_dir}/install-idamcp.sh"
    exit 10
fi

latest="$(upstream_version || true)"
if [[ -z "${latest}" ]]; then
    err "无法从 GitHub 读取 ida-mcp 上游版本"
    exit 1
fi

if [[ "${current_version}" == "${latest}" ]]; then
    log "ida-mcp ${current_version} 已是最新"
    exit 0
fi

if version_ge "${current_version}" "${latest}"; then
    log "已安装的 ida-mcp ${current_version} 高于上游 main 版本 ${latest}"
    exit 0
fi

log "发现更新：${current_version} -> ${latest}"
log "执行：${script_dir}/install-idamcp.sh"
exit 20
