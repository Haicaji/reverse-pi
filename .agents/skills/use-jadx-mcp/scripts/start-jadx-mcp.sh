#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

usage() {
    echo "Usage: $(basename "$0") [TARGET_DIR]" >&2
    echo "  TARGET_DIR  directory containing *.apk / *.dex files to open in JADX-GUI (optional)" >&2
}

# ---- parse optional target directory argument ----
TARGET_DIR=""
if [[ $# -gt 1 ]]; then
    echo "Error: too many arguments." >&2
    usage
    exit 1
elif [[ $# -eq 1 ]]; then
    TARGET_DIR="$1"
    if [[ ! -d "${TARGET_DIR}" ]]; then
        echo "Error: target directory not found: ${TARGET_DIR}" >&2
        exit 1
    fi
    TARGET_DIR="$(readlink -f "${TARGET_DIR}")"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 was not found in PATH." >&2
    exit 1
fi

if [[ ! -f "${JADX_MCP_SERVER}" ]]; then
    echo "Error: jadx_mcp_server.py not found at ${JADX_MCP_SERVER}." >&2
    exit 1
fi

if [[ ! -x "${JADX_GUI}" ]]; then
    echo "Error: jadx-gui not found at ${JADX_GUI}." >&2
    exit 1
fi

# ---- start MCP server ----
if is_running; then
    echo "JADX MCP is already running on port ${PORT}."
else
    # create the temporary directory for logs and PID file
    mkdir -p "${TMP_DIR}"

    nohup python3 "${JADX_MCP_SERVER}" \
        --http \
        --host 0.0.0.0 \
        --port "${PORT}" \
        --jadx-port "${JADX_PORT}" \
        >"${LOG_FILE}" 2>&1 </dev/null &

    PID=$!
    echo "${PID}" >"${PID_FILE}"

    # wait for the port to come up (up to 10 seconds)
    for _ in {1..20}; do
        if is_running; then
            break
        fi
        sleep 0.5
    done

    if ! is_running; then
        echo "Error: JADX MCP failed to start." >&2

        if [[ -f "${LOG_FILE}" ]]; then
            echo "----- ${LOG_FILE} -----" >&2
            tail -n 100 "${LOG_FILE}" >&2
        fi

        rm -f "${PID_FILE}"
        exit 1
    fi

    echo "JADX MCP started successfully."
    echo "PID: ${PID}"
    echo "Port: ${PORT}"
fi

# ---- open target files in JADX-GUI ----
if [[ -n "${TARGET_DIR}" ]]; then
    shopt -s nullglob
    FILES=("${TARGET_DIR}"/*.apk "${TARGET_DIR}"/*.dex)
    shopt -u nullglob

    if [[ ${#FILES[@]} -eq 0 ]]; then
        echo "Warning: no *.apk or *.dex files found in ${TARGET_DIR}." >&2
        exit 0
    fi

    nohup "${JADX_GUI}" "${FILES[@]}" >"${GUI_LOG_FILE}" 2>&1 </dev/null &
    echo "${!}" >"${GUI_PID_FILE}"
    echo "JADX-GUI launched with ${#FILES[@]} file(s) from ${TARGET_DIR}."
    echo "JADX-GUI PID: $(cat "${GUI_PID_FILE}")"
fi
