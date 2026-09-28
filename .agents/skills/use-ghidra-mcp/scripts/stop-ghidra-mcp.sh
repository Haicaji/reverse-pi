#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

# kill a process recorded in a PID file, falling back to pkill by command pattern
stop_by_pid_file() {
    local pid_file="$1"
    local pattern="$2"
    local stopped=false

    if [[ -f "${pid_file}" ]]; then
        local pid
        pid="$(cat "${pid_file}")"

        if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
            kill "${pid}" 2>/dev/null || true
            stopped=true
        fi
    fi

    if [[ "${stopped}" == false ]]; then
        pkill -TERM -f "${pattern}" || true
    fi

    rm -f "${pid_file}"
}

# ---------- 1. stop MCP Bridge (port 13337) ----------

if is_port_listening "${MCP_PORT}"; then
    stop_by_pid_file "${BRIDGE_PID_FILE}" "[b]ridge_mcp_ghidra.*--mcp-port ${MCP_PORT}"
else
    echo "Ghidra MCP bridge is not running on port ${MCP_PORT}."
    rm -f "${BRIDGE_PID_FILE}"
fi

# ---------- 2. stop Ghidra Headless (port 8089) ----------

if is_port_listening "${GHIDRA_PORT}"; then
    stop_by_pid_file "${GHIDRA_PID_FILE}" "[G]hidraMCPHeadlessServer.*--port ${GHIDRA_PORT}"
else
    echo "Ghidra headless server is not running on port ${GHIDRA_PORT}."
    rm -f "${GHIDRA_PID_FILE}"
fi

# wait up to 10 seconds for both ports to be released
for _ in {1..20}; do
    if ! is_port_listening "${MCP_PORT}" && ! is_port_listening "${GHIDRA_PORT}"; then
        echo "Ghidra MCP stopped successfully."
        exit 0
    fi
    sleep 0.5
done

echo "Error: Ghidra MCP is still listening on port ${MCP_PORT} or ${GHIDRA_PORT}." >&2
exit 1