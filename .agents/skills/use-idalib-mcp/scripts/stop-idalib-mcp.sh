#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

# check if the MCP server is already running on the specified port
is_running() {
    ss -ltn | grep -q ":${PORT}[[:space:]]"
}

if ! is_running; then
    echo "IDA Pro MCP is not running on port ${PORT}."
    rm -f "${PID_FILE}"
    exit 0
fi

STOPPED_BY_PID=false

if [[ -f "${PID_FILE}" ]]; then
    PID="$(cat "${PID_FILE}")"

    if [[ "${PID}" =~ ^[0-9]+$ ]] && kill -0 "${PID}" 2>/dev/null; then
        CMDLINE="$(tr '\0' ' ' <"/proc/${PID}/cmdline" 2>/dev/null || true)"

        if [[ "${CMDLINE}" == *"idalib-mcp"* ]] &&
           [[ "${CMDLINE}" == *"--port ${PORT}"* ]]; then
            kill "${PID}"
            STOPPED_BY_PID=true
        fi
    fi
fi

# If the PID file was not used to stop the process, use pkill to terminate it by matching the command line.
if [[ "${STOPPED_BY_PID}" == false ]]; then
    pkill -TERM -f "[i]dalib-mcp.*--port ${PORT}" || true
fi

# Wait for the process to stop, checking every 0.5 seconds for up to 5 seconds.
for _ in {1..10}; do
    if ! is_running; then
        rm -f "${PID_FILE}"
        echo "IDA Pro MCP stopped successfully."
        exit 0
    fi

    sleep 0.5
done

echo "Error: IDA Pro MCP is still listening on port ${PORT}." >&2
exit 1