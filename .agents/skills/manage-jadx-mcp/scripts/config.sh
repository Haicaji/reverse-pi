#!/usr/bin/env bash

PORT=8651
JADX_PORT=8650
WORK_DIR="$(pwd -P)"

# State directory. Must be cwd-independent: start/check/stop are frequently run
# from different directories, and only one instance can own ${PORT} anyway.
# Override with JADX_MCP_STATE_DIR if a specific location is required.
TMP_DIR="${JADX_MCP_STATE_DIR:-${XDG_STATE_HOME:-${HOME}/.local/state}/jadx-mcp}"
LOG_FILE="${TMP_DIR}/jadx-mcp.log"
PID_FILE="${TMP_DIR}/jadx-mcp.pid"
GUI_PID_FILE="${TMP_DIR}/jadx-gui.pid"
GUI_LOG_FILE="${TMP_DIR}/jadx-gui.log"
GUI_CMD_FILE="${TMP_DIR}/jadx-gui.cmdline"

JADX_MCP_SERVER="$HOME/MCPServer/jadx-mcp-server/jadx_mcp_server.py"
JADX_GUI="$HOME/Program/jadx-1.5.6/bin/jadx-gui"

# Python interpreter used to run the MCP server. Defaults to python3 from PATH;
# replace this with an absolute path to pin a specific environment.
PYTHON="${PYTHON:-$(command -v python3 2>/dev/null || true)}"

# How long to wait (seconds) for JADX-GUI to open the plugin port after launch.
JADX_GUI_START_TIMEOUT="${JADX_GUI_START_TIMEOUT:-240}"

# Extra variables that must never be touched by scrub_snap_env (space separated).
JADX_GUI_ENV_KEEP="${JADX_GUI_ENV_KEEP:-}"

# check if a TCP port is in LISTEN state
port_listening() {
    local port="$1"
    ss -ltn 2>/dev/null | grep -q ":${port}[[:space:]]"
}

# check if the MCP server is already running on the specified port
is_running() {
    port_listening "${PORT}"
}

# print the tail of a log file to stderr
show_log_tail() {
    local file="$1"
    [[ -f "${file}" ]] || return 0
    echo "----- ${file} (tail) -----" >&2
    tail -n 40 "${file}" >&2
}

# ---------------------------------------------------------------------------
# Snap environment scrubbing
# ---------------------------------------------------------------------------
# Snap-packaged desktop apps (VS Code, Chromium, etc.) export GTK / GDK / GIO /
# LD paths that point inside /snap/<package>/current/... into every shell they
# spawn. Those libraries are glibc-private to the snap, so any external
# JVM/Swing process that picks them up dies immediately with:
#
#   java: symbol lookup error: /snap/core20/current/lib/.../libpthread.so.0:
#   undefined symbol: __libc_pthread_init, version GLIBC_PRIVATE
#
# Rather than blacklisting variable names (which differs per snap and per app
# version), drop every path fragment that lives under a /snap/ tree. Path-list
# variables keep their remaining entries; scalar variables pointing into a snap
# are unset entirely. Variables listed in JADX_GUI_ENV_KEEP are left alone.
scrub_snap_env() {
    local var val part joined
    local -a parts kept

    for var in $(compgen -e); do
        case "${var}" in
            # Keep the shell/host basics and the snap bookkeeping variables as-is.
            PATH|PWD|OLDPWD|SHLVL|_|SNAP|SNAP_*) continue ;;
        esac

        if [[ -n "${JADX_GUI_ENV_KEEP}" && " ${JADX_GUI_ENV_KEEP} " == *" ${var} "* ]]; then
            continue
        fi

        val="${!var}"
        [[ "${val}" == *"/snap/"* ]] || continue

        parts=()
        kept=()
        IFS=':' read -r -a parts <<< "${val}"
        for part in "${parts[@]}"; do
            [[ -z "${part}" ]] && continue
            [[ "${part}" == *"/snap/"* ]] && continue
            kept+=("${part}")
        done

        if [[ ${#kept[@]} -eq 0 ]]; then
            unset "${var}"
        else
            joined="$(IFS=':'; printf '%s' "${kept[*]}")"
            export "${var}=${joined}"
        fi
    done
}

# Resolve the java binary JADX-GUI would use (mirrors the bundled jadx-gui wrapper).
resolve_javacmd() {
    if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
        echo "${JAVA_HOME}/bin/java"
        return 0
    fi
    command -v java 2>/dev/null || true
}

# Fail fast with a useful message instead of letting JADX-GUI die silently.
check_java_runnable() {
    local javacmd log
    javacmd="$(resolve_javacmd)"

    if [[ -z "${javacmd}" ]]; then
        echo "Error: no java runtime found (JAVA_HOME unset and 'java' not in PATH)." >&2
        return 1
    fi

    log="$(mktemp)"
    if ! "${javacmd}" -version >"${log}" 2>&1; then
        echo "Error: '${javacmd}' cannot start in the current environment:" >&2
        sed 's/^/    /' "${log}" >&2
        rm -f "${log}"
        echo "Hint: the usual cause is a snap-injected GTK/LD library path; run with" >&2
        echo "      JADX_GUI_ENV_KEEP='' (default) or launch from a non-snap terminal." >&2
        return 1
    fi

    rm -f "${log}"
    return 0
}

# Launch JADX-GUI with the given APK/DEX files and wait until the embedded
# JADX AI MCP plugin is actually serving on ${JADX_PORT}. Returns non-zero and
# prints the GUI log tail on failure.
launch_jadx_gui() {
    local -a files=("$@")
    local gui_pid waited=0 timeout=$((JADX_GUI_START_TIMEOUT * 2))

    mkdir -p "${TMP_DIR}"
    : >"${GUI_LOG_FILE}"

    # Never run a second JADX-GUI: the plugin port can only be bound once, so a
    # second instance would fail silently and leave the tracked PID pointing at
    # the wrong process.
    if port_listening "${JADX_PORT}"; then
        echo "JADX-GUI MCP plugin is already serving on port ${JADX_PORT}; not launching another instance."
        echo "Hint: run stop-jadx-mcp.sh first to reopen a different target." >&2
        return 0
    fi

    # 1) strip snap pollution, 2) make sure java survives it. Both failure
    # modes used to be silent: the server came up on ${PORT} while every tool
    # call failed because the GUI had died.
    scrub_snap_env
    check_java_runnable || return 1

    if command -v setsid >/dev/null 2>&1; then
        nohup setsid "${JADX_GUI}" "${files[@]}" \
            >"${GUI_LOG_FILE}" 2>&1 </dev/null &
    else
        nohup "${JADX_GUI}" "${files[@]}" \
            >"${GUI_LOG_FILE}" 2>&1 </dev/null &
    fi

    gui_pid=$!
    echo "${gui_pid}" >"${GUI_PID_FILE}"
    printf '%s\n' "${JADX_GUI}" "${files[@]}" >"${GUI_CMD_FILE}"

    echo "Waiting for JADX-GUI to open port ${JADX_PORT} (timeout ${JADX_GUI_START_TIMEOUT}s)..."

    while (( waited < timeout )); do
        if ! kill -0 "${gui_pid}" 2>/dev/null; then
            echo "Error: JADX-GUI exited during startup (PID ${gui_pid})." >&2
            show_log_tail "${GUI_LOG_FILE}"
            rm -f "${GUI_PID_FILE}" "${GUI_CMD_FILE}"
            return 1
        fi

        if port_listening "${JADX_PORT}"; then
            echo "JADX-GUI launched with ${#files[@]} file(s)."
            echo "JADX-GUI PID: ${gui_pid}"
            echo "JADX AI MCP plugin port: ${JADX_PORT}"
            return 0
        fi

        sleep 0.5
        waited=$((waited + 1))
    done

    echo "Error: JADX-GUI did not open port ${JADX_PORT} within ${JADX_GUI_START_TIMEOUT}s." >&2
    show_log_tail "${GUI_LOG_FILE}"
    return 1
}
