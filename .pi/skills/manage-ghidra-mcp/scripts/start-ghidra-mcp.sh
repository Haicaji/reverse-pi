#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

mkdir -p "${TMP_DIR}"

if [[ ! -d "${GHIDRA_HOME}" ]]; then
    echo "Error: GHIDRA_HOME does not exist: ${GHIDRA_HOME}" >&2
    exit 1
fi

if [[ ! -d "${GHIDRA_MCP_DIR}" ]]; then
    echo "Error: Ghidra MCP directory does not exist: ${GHIDRA_MCP_DIR}" >&2
    exit 1
fi

if [[ -z "${PYTHON}" || ! -x "${PYTHON}" ]]; then
    echo "Error: Python interpreter not found: ${PYTHON:-<empty>}. Set python in the [ghidra] table of config.toml or add python3 to PATH." >&2
    exit 1
fi

# ---------- 1. Ghidra Headless MCP Server ----------

GHIDRA_STARTED=0

if is_port_listening "${GHIDRA_PORT}"; then
    echo "Ghidra headless server is already running on port ${GHIDRA_PORT}."
else
    cd "${GHIDRA_MCP_DIR}"

    MCP_JAR="$(
        find target -maxdepth 1 -type f -name 'GhidraMCP-*.jar' -print \
        | sort | head -n1
    )"

    if [[ -z "${MCP_JAR}" ]]; then
        echo "Error: target/GhidraMCP-*.jar was not found." >&2
        exit 1
    fi

    CP="${MCP_JAR}"
    for jar in "${GHIDRA_HOME}"/Ghidra/{Framework,Features,Processors}/*/lib/*.jar; do
        [[ -f "${jar}" ]] && CP="${CP}:${jar}"
    done

    nohup java \
        -Xmx4g \
        -Dghidra.home="${GHIDRA_HOME}" \
        -classpath "${CP}" \
        com.xebyte.headless.GhidraMCPHeadlessServer \
        --bind "${GHIDRA_HOST}" \
        --port "${GHIDRA_PORT}" \
        >"${GHIDRA_LOG}" 2>&1 </dev/null &

    PID=$!
    echo "${PID}" >"${GHIDRA_PID_FILE}"
    GHIDRA_STARTED=1

    if wait_for_port "${GHIDRA_PORT}" 20; then
        echo "Ghidra headless server started successfully."
        echo "PID: ${PID}, Port: ${GHIDRA_PORT}"
    else
        echo "Error: Ghidra headless server failed to start." >&2
        show_log_tail "${GHIDRA_LOG}"
        rm -f "${GHIDRA_PID_FILE}"
        exit 1
    fi
fi

# ---------- 2. MCP Bridge ----------

if is_port_listening "${MCP_PORT}"; then
    echo "Ghidra MCP bridge is already running on port ${MCP_PORT}."
    exit 0
fi

nohup "${PYTHON}" \
    -m bridge_mcp_ghidra \
    --transport streamable-http \
    --mcp-host "${MCP_HOST}" \
    --mcp-port "${MCP_PORT}" \
    >"${BRIDGE_LOG}" 2>&1 </dev/null &

PID=$!
echo "${PID}" >"${BRIDGE_PID_FILE}"

if wait_for_port "${MCP_PORT}" 15; then
    echo "Ghidra MCP started successfully."
    echo "Bridge: ${MCP_HOST}:${MCP_PORT} (PID ${PID})"
    exit 0
fi

echo "Error: Ghidra MCP bridge failed to start." >&2
show_log_tail "${BRIDGE_LOG}"
rm -f "${BRIDGE_PID_FILE}"

if [[ "${GHIDRA_STARTED}" -eq 1 && -f "${GHIDRA_PID_FILE}" ]]; then
    GHIDRA_PID="$(cat "${GHIDRA_PID_FILE}")"
    kill "${GHIDRA_PID}" 2>/dev/null || true
    rm -f "${GHIDRA_PID_FILE}"
fi

exit 1