#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/config.sh"

STOPPED=false

if is_running; then
    STOPPED_BY_PID=false

    if [[ -f "${PID_FILE}" ]]; then
        PID="$(cat "${PID_FILE}")"

        if [[ "${PID}" =~ ^[0-9]+$ ]] && kill -0 "${PID}" 2>/dev/null; then
            CMDLINE="$(tr '\0' ' ' <"/proc/${PID}/cmdline" 2>/dev/null || true)"

            if [[ "${CMDLINE}" == *"jadx_mcp_server.py"* ]] &&
               [[ "${CMDLINE}" == *"--port ${PORT}"* ]]; then
                kill "${PID}"
                STOPPED_BY_PID=true
            fi
        fi
    fi

    # If the PID file was not used to stop the process, use pkill to terminate it by matching the command line.
    if [[ "${STOPPED_BY_PID}" == false ]]; then
        pkill -TERM -f "[j]adx_mcp_server.py.*--port ${PORT}" || true
    fi

    # Wait for the process to stop, checking every 0.5 seconds for up to 5 seconds.
    for _ in {1..10}; do
        if ! is_running; then
            STOPPED=true
            break
        fi
        sleep 0.5
    done

    if [[ "${STOPPED}" == false ]]; then
        echo "Error: JADX MCP is still listening on port ${PORT}." >&2
        exit 1
    fi
fi

rm -f "${PID_FILE}"

# ---- stop JADX-GUI if it was launched by the start script ----
if [[ -f "${GUI_PID_FILE}" ]]; then
    GUI_PID="$(cat "${GUI_PID_FILE}")"

    if [[ "${GUI_PID}" =~ ^[0-9]+$ ]] && kill -0 "${GUI_PID}" 2>/dev/null; then
        # The GUI is launched via setsid, so its PID is also its process group
        # id: kill the group so no java child survives the wrapper.
        kill -TERM -- "-${GUI_PID}" 2>/dev/null || kill -TERM "${GUI_PID}" 2>/dev/null || true

        GUI_STOPPED=false
        for _ in {1..20}; do
            if ! port_listening "${JADX_PORT}"; then
                GUI_STOPPED=true
                break
            fi
            sleep 0.5
        done

        if [[ "${GUI_STOPPED}" == true ]]; then
            echo "JADX-GUI (PID ${GUI_PID}) stopped."
        else
            echo "Warning: port ${JADX_PORT} is still open after stopping JADX-GUI (PID ${GUI_PID})." >&2
        fi
    fi

    rm -f "${GUI_PID_FILE}" "${GUI_CMD_FILE}"
fi

if [[ "${STOPPED}" == true ]]; then
    echo "JADX MCP stopped successfully."
else
    echo "JADX MCP is not running on port ${PORT}."
fi
exit 0
