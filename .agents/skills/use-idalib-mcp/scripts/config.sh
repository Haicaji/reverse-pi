#!/usr/bin/env bash

PORT=13336
WORK_DIR="$(pwd -P)"
TMP_DIR="${WORK_DIR}/tmp/idalib-mcp"
LOG_FILE="${TMP_DIR}/idalib-mcp.log"
PID_FILE="${TMP_DIR}/idalib-mcp.pid"

# check if the MCP server is already running on the specified port
is_running() {
    ss -ltn | grep -q ":${PORT}[[:space:]]"
}
