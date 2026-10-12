#!/usr/bin/env bash

GHIDRA_HOME="$HOME/Program/ghidra_12.1.3"
GHIDRA_MCP_DIR="$HOME/MCPServer/ghidra-mcp"
PYTHON="$HOME/miniconda3/envs/ghidra-mcp/bin/python"

GHIDRA_HOST="127.0.0.1"
GHIDRA_PORT=8089

MCP_HOST="0.0.0.0"
MCP_PORT=13337

WORK_DIR="$(pwd -P)"
TMP_DIR="${WORK_DIR}/.tmp/ghidra-mcp"

GHIDRA_LOG="${TMP_DIR}/ghidra-headless.log"
GHIDRA_PID_FILE="${TMP_DIR}/ghidra-headless.pid"

BRIDGE_LOG="${TMP_DIR}/bridge-mcp-ghidra.log"
BRIDGE_PID_FILE="${TMP_DIR}/bridge-mcp-ghidra.pid"

# check if a given port is listening
is_port_listening() {
    local port="$1"
    ss -ltn | grep -qE ":${port}[[:space:]]"
}

# wait for a given port to start listening, with a timeout (seconds)
wait_for_port() {
    local port="$1"
    local timeout="${2:-15}"

    for ((i = 0; i < timeout; i++)); do
        if is_port_listening "${port}"; then
            return 0
        fi
        sleep 1
    done

    return 1
}

# show the last 100 lines of a log file
show_log_tail() {
    local log_file="$1"

    if [[ -f "${log_file}" ]]; then
        echo "----- ${log_file} -----" >&2
        tail -n 100 "${log_file}" >&2
    fi
}
