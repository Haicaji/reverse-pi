#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

if ! command -v ss >/dev/null 2>&1; then
    echo "Error: ss command was not found." >&2
    exit 2
fi

if ss -ltn | grep -q ":${PORT}[[:space:]]"; then
    echo "JADX MCP is running on port ${PORT}."
    exit 0
fi

echo "JADX MCP is not running on port ${PORT}."
exit 1
