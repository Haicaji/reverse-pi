#!/usr/bin/env bash

# Shared, user-editable settings live in <repo>/config.toml. Values are read
# only from that file; environment variables are not consulted.

# ---------------------------------------------------------------------------
# Inline TOML reader for the repository-level config.toml.
#
# This block is intentionally duplicated in each skill's config.sh so that the
# skill tree stays self-contained; keep the three copies in sync.
#
# The block is followed by calls like:
#
#   toml_export <section> SHELL_VAR=toml_key [...]
#
# Configuration values are read only from config.toml; environment variables
# are not consulted. A missing key unsets the variable so the caller's default
# applies.
#
# Only a small TOML subset is supported: tables, bare keys, basic/literal
# strings, integers, booleans and comments. Arrays, inline tables and
# multi-line strings are rejected with an error.

_config_script_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
_config_repo_root="$(cd "${_config_script_dir}/../../../.." && pwd -P)"
REVERSE_PI_CONFIG_FILE="${_config_repo_root}/config.toml"

if [[ ! -f "${REVERSE_PI_CONFIG_FILE}" ]]; then
    echo "Error: shared config file not found: ${REVERSE_PI_CONFIG_FILE}" >&2
    echo "Create it at the repository root; see README.md for the expected tables." >&2
    exit 1
fi

# Trim leading and trailing whitespace.
_toml_trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# Remove a TOML comment while preserving '#' inside quoted strings.
_toml_strip_comment() {
    local value="$1" out="" ch quote="" i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        if [[ "${quote}" == '"' ]]; then
            if [[ "${ch}" == '\' ]]; then
                out+="${ch}${value:i+1:1}"
                i=$((i + 1))
                continue
            elif [[ "${ch}" == '"' ]]; then
                quote=""
            fi
        elif [[ "${quote}" == "'" ]]; then
            if [[ "${ch}" == "'" ]]; then
                quote=""
            fi
        else
            if [[ "${ch}" == '#' ]]; then
                break
            elif [[ "${ch}" == '"' || "${ch}" == "'" ]]; then
                quote="${ch}"
            fi
        fi
        out+="${ch}"
    done
    printf '%s' "${out}"
}

# Decode the escape sequences of a TOML basic string.
_toml_unescape_basic() {
    local value="$1" out="" ch hex i
    for ((i = 0; i < ${#value}; i++)); do
        ch="${value:i:1}"
        if [[ "${ch}" != '\' ]]; then
            out+="${ch}"
            continue
        fi

        i=$((i + 1))
        ch="${value:i:1}"
        case "${ch}" in
            '"') out+='"' ;;
            '\') out+='\' ;;
            n) out+=$'\n' ;;
            t) out+=$'\t' ;;
            r) out+=$'\r' ;;
            b) out+=$'\b' ;;
            f) out+=$'\f' ;;
            u)
                hex="${value:i+1:4}"
                if [[ "${hex}" =~ ^[0-9A-Fa-f]{4}$ ]]; then
                    out+="$(printf "\\u${hex}")"
                    i=$((i + 4))
                else
                    out+='\u'
                fi
                ;;
            U)
                hex="${value:i+1:8}"
                if [[ "${hex}" =~ ^[0-9A-Fa-f]{8}$ ]]; then
                    out+="$(printf "\\U${hex}")"
                    i=$((i + 8))
                else
                    out+='\U'
                fi
                ;;
            *) out+="\\${ch}" ;;
        esac
    done
    printf '%s' "${out}"
}

# Convert a raw TOML scalar into its shell string value.
_toml_decode_value() {
    local value="$1"
    if [[ "${value}" == \"*\" ]] && [[ "${value}" != '"' ]]; then
        value="${value#\"}"
        value="${value%\"}"
        _toml_unescape_basic "${value}"
    elif [[ "${value}" == \'*\' ]] && [[ "${value}" != "'" ]]; then
        value="${value#\'}"
        value="${value%\'}"
        printf '%s' "${value}"
    elif [[ "${value}" =~ ^(true|false|-?[0-9]+)$ ]]; then
        printf '%s' "${value}"
    else
        return 1
    fi
}

# toml_get <section> <key>
# Prints the value and returns 0 when found, 1 when absent, 2 when malformed.
toml_get() {
    local section="$1" key="$2"
    local line trimmed current_section="" raw key_part
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="$(_toml_strip_comment "${line}")"
        trimmed="$(_toml_trim "${line}")"
        [[ -z "${trimmed}" ]] && continue

        if [[ "${trimmed}" =~ ^\[([^]]+)\]$ ]]; then
            current_section="$(_toml_trim "${BASH_REMATCH[1]}")"
            continue
        fi

        [[ "${current_section}" == "${section}" ]] || continue
        [[ "${trimmed}" == *=* ]] || continue

        key_part="$(_toml_trim "${trimmed%%=*}")"
        [[ "${key_part}" == "${key}" ]] || continue

        raw="$(_toml_trim "${trimmed#*=}")"
        if ! _toml_decode_value "${raw}"; then
            return 2
        fi
        return 0
    done <"${REVERSE_PI_CONFIG_FILE}"
    return 1
}

# toml_export <section> SHELL_VAR=toml_key [...]
# Assigns config.toml values to shell variables. Environment variables are not
# consulted; a missing key unsets the variable so the caller's default applies.
toml_export() {
    local section="$1"
    shift
    local pair name key value status
    for pair in "$@"; do
        name="${pair%%=*}"
        key="${pair#*=}"

        if value="$(toml_get "${section}" "${key}")"; then
            status=0
        else
            status=$?
        fi

        if [[ "${status}" -eq 2 ]]; then
            echo "Error: unsupported or malformed value for [${section}].${key} in ${REVERSE_PI_CONFIG_FILE}." >&2
            exit 1
        fi

        if [[ "${status}" -eq 1 ]]; then
            unset "${name}"
            continue
        fi

        printf -v "${name}" '%s' "${value}"
    done
}

# Expand a leading "~" or "~/" to $HOME.
expand_tilde() {
    local value="$1"
    if [[ "${value}" == "~" ]]; then
        printf '%s' "${HOME}"
    elif [[ "${value}" == "~/"* ]]; then
        printf '%s/%s' "${HOME}" "${value#\~/}"
    else
        printf '%s' "${value}"
    fi
}

toml_export jadx \
    PORT=port \
    JADX_PORT=jadx_port \
    JADX_MCP_SERVER=mcp_server \
    JADX_GUI=gui \
    PYTHON=python \
    JADX_GUI_START_TIMEOUT=gui_start_timeout \
    JADX_STATE_DIR=state_dir \
    JADX_GUI_ENV_KEEP=gui_env_keep

# Built-in defaults, used when a key is absent from config.toml.
: "${PORT:=8651}"
: "${JADX_PORT:=8650}"
: "${JADX_MCP_SERVER:=${HOME}/MCPServer/jadx-mcp-server/jadx_mcp_server.py}"
: "${JADX_GUI:=${HOME}/Program/jadx-1.5.6/bin/jadx-gui}"
: "${PYTHON:=$(command -v python3 2>/dev/null || true)}"
: "${JADX_GUI_START_TIMEOUT:=240}"
: "${JADX_STATE_DIR:=${HOME}/.local/state/jadx-mcp}"
: "${JADX_GUI_ENV_KEEP:=}"

JADX_MCP_SERVER="$(expand_tilde "${JADX_MCP_SERVER}")"
JADX_GUI="$(expand_tilde "${JADX_GUI}")"

WORK_DIR="$(pwd -P)"

# State directory. Must be cwd-independent: start/check/stop are frequently run
# from different directories, and only one instance can own ${PORT} anyway.
TMP_DIR="$(expand_tilde "${JADX_STATE_DIR}")"
LOG_FILE="${TMP_DIR}/jadx-mcp.log"
PID_FILE="${TMP_DIR}/jadx-mcp.pid"
GUI_PID_FILE="${TMP_DIR}/jadx-gui.pid"
GUI_LOG_FILE="${TMP_DIR}/jadx-gui.log"
GUI_CMD_FILE="${TMP_DIR}/jadx-gui.cmdline"

# Extra variables that must never be touched by scrub_snap_env (space separated).

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
        echo "Hint: the usual cause is a snap-injected GTK/LD library path. Launch from" >&2
        echo "      a non-snap terminal, or adjust gui_env_keep in config.toml." >&2
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
