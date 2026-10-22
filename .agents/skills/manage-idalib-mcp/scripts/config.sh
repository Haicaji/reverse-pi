#!/usr/bin/env bash

# Shared, user-editable settings live in <repo>/config.toml. The port is read
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

toml_export idalib PORT=port

# Built-in default, used when the key is absent from config.toml.
: "${PORT:=13336}"

WORK_DIR="$(pwd -P)"
TMP_DIR="${WORK_DIR}/.tmp/idalib-mcp"
LOG_FILE="${TMP_DIR}/idalib-mcp.log"
PID_FILE="${TMP_DIR}/idalib-mcp.pid"

# check if the MCP server is already running on the specified port
is_running() {
    ss -ltn | grep -q ":${PORT}[[:space:]]"
}
