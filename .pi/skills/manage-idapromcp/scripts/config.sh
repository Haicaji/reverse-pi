#!/usr/bin/env bash

# Shared configuration and helpers for the manage-idapromcp Skill.
#
# ida-mcp is the official Hex-Rays IDA MCP server. It runs headlessly on top of
# idalib, so it needs an installed and licensed IDA Pro 9.4+ plus Python 3.11+.
# This Skill detects IDA Pro and manages ida-mcp; it never installs IDA Pro or a
# Python runtime.

set -euo pipefail

_config_script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
REPO_ROOT="$(cd "${_config_script_dir}/../../../.." && pwd -P)"

# Runtime state (PID file) lives under the repo-local tools directory, which
# is gitignored.
STATE_DIR="${IDA_MCP_STATE_DIR:-${REPO_ROOT}/tools/ida-mcp}"
PID_FILE="${STATE_DIR}/ida-mcp.pid"

MCP_CONFIG="${REPO_ROOT}/.pi/mcp.json"
MCP_SERVER_NAME="IDA"
MCP_SERVER_DESCRIPTION="Official Hex-Rays IDA MCP server (ida-mcp): headless IDA Pro reverse engineering via idalib (decompile, disasm, xrefs, strings, types)."

# The HTTP MCP endpoint. Bind to loopback by default; only the port and host
# used for launching/probing are configurable.
DEFAULT_HTTP_HOST="127.0.0.1"
DEFAULT_HTTP_PORT="8737"
HTTP_HOST="${IDA_MCP_HTTP_HOST:-${DEFAULT_HTTP_HOST}}"
HTTP_PORT="${IDA_MCP_HTTP_PORT:-${DEFAULT_HTTP_PORT}}"

case "${HTTP_HOST}" in
    0.0.0.0|::|"[::]")
        _mcp_host="127.0.0.1"
        ;;
    *)
        _mcp_host="${HTTP_HOST}"
        ;;
esac
MCP_URL="http://${_mcp_host}:${HTTP_PORT}/mcp"

# IDA Pro creates this directory on first start. It is also the marker used to
# decide whether IDA Pro is installed on the machine.
IDAPRO_USER_DIR="${IDAPRO_USER_DIR:-${HOME}/.idapro}"

# Python environment that receives ida-mcp. Override with IDA_MCP_PYTHON or the
# --python option of install-idamcp.sh.
IDA_MCP_PYTHON="${IDA_MCP_PYTHON:-python3}"
IDA_MCP_MIN_PYTHON="3.11"

IDA_MCP_REPO_URL="https://github.com/HexRaysSA/ida-mcp.git"
IDA_MCP_PYPROJECT_URL="https://raw.githubusercontent.com/HexRaysSA/ida-mcp/main/pyproject.toml"
IDA_MCP_PYPROJECT_FALLBACK_URL="https://github.com/HexRaysSA/ida-mcp/raw/main/pyproject.toml"

log() {
    printf '[ida-mcp] %s\n' "$*"
}

warn() {
    printf '[ida-mcp] WARNING: %s\n' "$*" >&2
}

err() {
    printf '[ida-mcp] ERROR: %s\n' "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

normalize_version() {
    printf '%s\n' "${1#v}"
}

# Compare two dotted versions with GNU sort -V.
version_ge() {
    local left="$1" right="$2"
    [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n 1)" == "${left}" ]]
}

python_executable() {
    "${IDA_MCP_PYTHON}" -c 'import sys; print(sys.executable)' 2>/dev/null
}

python_version() {
    "${IDA_MCP_PYTHON}" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null
}

python_scripts_dir() {
    "${IDA_MCP_PYTHON}" -c 'import sysconfig; print(sysconfig.get_path("scripts"))' 2>/dev/null
}

python_supported() {
    "${IDA_MCP_PYTHON}" - "${IDA_MCP_MIN_PYTHON}" <<'PY' >/dev/null 2>&1
import sys

minimum = tuple(int(part) for part in sys.argv[1].split("."))
raise SystemExit(0 if sys.version_info[:len(minimum)] >= minimum else 1)
PY
}

# Print the installed ida-mcp version, or fail when it is not installed.
idamcp_version() {
    "${IDA_MCP_PYTHON}" - <<'PY' 2>/dev/null
import importlib.metadata

try:
    print(importlib.metadata.version("ida-mcp"))
except importlib.metadata.PackageNotFoundError:
    raise SystemExit(1)
PY
}

# Resolve the ida-mcp console script inside the selected Python environment.
idamcp_command() {
    local scripts
    scripts="$(python_scripts_dir || true)"
    if [[ -n "${scripts}" && -x "${scripts}/ida-mcp" ]]; then
        printf '%s\n' "${scripts}/ida-mcp"
        return 0
    fi
    command -v ida-mcp 2>/dev/null
}

# Print the version declared on the upstream main branch, or fail.
upstream_version() {
    local version="" url
    have curl || return 1
    for url in "${IDA_MCP_PYPROJECT_URL}" "${IDA_MCP_PYPROJECT_FALLBACK_URL}"; do
        version="$(curl -fsSL --max-time 20 "${url}" 2>/dev/null \
            | sed -n 's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
            | sed -n '1p')"
        [[ -n "${version}" ]] && break
    done
    [[ -n "${version}" ]] || return 1
    normalize_version "${version}"
}

if ! [[ "${HTTP_PORT}" =~ ^[0-9]+$ ]] || ((10#${HTTP_PORT} < 1 || 10#${HTTP_PORT} > 65535)); then
    err "invalid IDA_MCP_HTTP_PORT: ${HTTP_PORT}"
    exit 1
fi

if [[ -z "${HTTP_HOST}" ]]; then
    err "IDA_MCP_HTTP_HOST must not be empty"
    exit 1
fi

require_http_tools() {
    local tool
    for tool in ss curl; do
        if ! have "${tool}"; then
            err "缺少命令：${tool}；本 Skill 不会自行安装，请处理后重试"
            exit 12
        fi
    done
}

pid_alive() {
    local pid="$1"
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null
}

read_pid() {
    [[ -f "${PID_FILE}" ]] || return 1
    tr -cd '0-9' <"${PID_FILE}"
}

# True when the PID is an ida-mcp HTTP process bound to the configured port.
pid_is_idamcp_http() {
    local pid="$1" cmdline
    [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
    [[ -r "/proc/${pid}/cmdline" ]] || return 1
    cmdline="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)"
    [[ "${cmdline}" == *"ida-mcp"* ]] \
        && [[ "${cmdline}" == *" http"* ]] \
        && [[ "${cmdline}" == *"--port ${HTTP_PORT}"* ]]
}

port_in_use() {
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${HTTP_PORT}$"
}

find_pid_by_port() {
    ss -ltnpH 2>/dev/null \
        | grep -E "[:.]${HTTP_PORT}[[:space:]]" \
        | sed -n 's/.*pid=\([0-9]*\).*/\1/p' \
        | sed -n '1p'
}

# Send an MCP initialize request to the HTTP endpoint.
mcp_probe() {
    local body
    have curl || return 1
    body="$(curl -fsS --max-time 10 -X POST "${MCP_URL}" \
        -H 'Content-Type: application/json' \
        -H 'Accept: application/json, text/event-stream' \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"reverse-pi","version":"1.0"}}}' \
        2>/dev/null)" || return 1
    [[ "${body}" == *'"serverInfo"'* ]]
}

wait_for_mcp() {
    local timeout="$1" i
    for ((i = 0; i < timeout; i++)); do
        if mcp_probe; then
            return 0
        fi
        sleep 1
    done
    return 1
}
