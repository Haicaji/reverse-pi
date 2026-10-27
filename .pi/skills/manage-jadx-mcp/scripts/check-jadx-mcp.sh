#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

if ! command -v ss >/dev/null 2>&1; then
    echo "Error: ss command was not found." >&2
    exit 2
fi

# Report both layers: the MCP server (${PORT}) is useless if the JADX AI MCP
# plugin inside JADX-GUI (${JADX_PORT}) is not up.
MCP_UP=false
GUI_UP=false

is_running && MCP_UP=true
port_listening "${JADX_PORT}" && GUI_UP=true

if [[ "${MCP_UP}" == true ]]; then
    echo "JADX MCP is running on port ${PORT}."
else
    echo "JADX MCP is NOT running on port ${PORT}."
fi

if [[ "${GUI_UP}" == true ]]; then
    echo "JADX-GUI MCP plugin is serving on port ${JADX_PORT}."
else
    echo "JADX-GUI MCP plugin is NOT serving on port ${JADX_PORT} (tool calls will fail)."
fi

if [[ "${MCP_UP}" == true && "${GUI_UP}" != true ]]; then
    echo "Log: ${GUI_LOG_FILE}"
    [[ -f "${GUI_LOG_FILE}" ]] && tail -n 10 "${GUI_LOG_FILE}"
fi

if [[ "${MCP_UP}" == true && "${GUI_UP}" == true ]]; then
    exit 0
fi

exit 1
