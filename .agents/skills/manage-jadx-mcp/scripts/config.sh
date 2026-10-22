#!/usr/bin/env bash

PORT=8651
JADX_PORT=8650
WORK_DIR="$(pwd -P)"
TMP_DIR="${WORK_DIR}/.tmp/jadx-mcp"
LOG_FILE="${TMP_DIR}/jadx-mcp.log"
PID_FILE="${TMP_DIR}/jadx-mcp.pid"
GUI_PID_FILE="${TMP_DIR}/jadx-gui.pid"
GUI_LOG_FILE="${TMP_DIR}/jadx-gui.log"

JADX_MCP_SERVER="$HOME/MCPServer/jadx-mcp-server/jadx_mcp_server.py"
JADX_GUI="$HOME/Program/jadx-1.5.6/bin/jadx-gui"

# Python interpreter used to run the MCP server. Defaults to python3 from PATH;
# replace this with an absolute path to pin a specific environment.
PYTHON="${PYTHON:-$(command -v python3 2>/dev/null || true)}"

# check if the MCP server is already running on the specified port
is_running() {
    ss -ltn | grep -q ":${PORT}[[:space:]]"
}
