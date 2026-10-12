#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

# check if the MCP server is already running on the specified port
is_running() {
    ss -ltn | grep -q ":${PORT}[[:space:]]"
}

if is_running; then
    echo "IDA Pro MCP is already running on port ${PORT}."
    exit 0
fi

# check if the idalib-mcp command is available in the PATH
if ! command -v idalib-mcp >/dev/null 2>&1; then
    echo "Error: idalib-mcp was not found in PATH." >&2
    exit 1
fi

# create the temporary directory for logs and PID file
mkdir -p "${TMP_DIR}"

nohup idalib-mcp \
    --host 0.0.0.0 \
    --port "${PORT}" \
    >"${LOG_FILE}" 2>&1 </dev/null &

PID=$!
echo "${PID}" >"${PID_FILE}"

sleep 2

if is_running; then
    echo "IDA Pro MCP started successfully."
    echo "PID: ${PID}"
    echo "Port: ${PORT}"
    exit 0
fi

echo "Error: IDA Pro MCP failed to start." >&2

if [[ -f "${LOG_FILE}" ]]; then
    echo "----- ${LOG_FILE} -----" >&2
    tail -n 100 "${LOG_FILE}" >&2
fi

rm -f "${PID_FILE}"
exit 1