#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

if ! command -v ss >/dev/null 2>&1; then
    echo "Error: ss command was not found." >&2
    exit 2
fi

FAILED=0

if is_port_listening "${GHIDRA_PORT}"; then
    echo "Ghidra headless server is running on port ${GHIDRA_PORT}."
else
    echo "Ghidra headless server is not running on port ${GHIDRA_PORT}."
    FAILED=1
fi

if is_port_listening "${MCP_PORT}"; then
    echo "Ghidra MCP bridge is running on port ${MCP_PORT}."
else
    echo "Ghidra MCP bridge is not running on port ${MCP_PORT}."
    FAILED=1
fi

exit "${FAILED}"