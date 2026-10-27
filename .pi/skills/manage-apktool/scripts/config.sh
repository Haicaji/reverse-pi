#!/usr/bin/env bash

# Shared configuration and helpers for the apktool Skill.
#
# apktool is installed as a repository-local tool under <repo>/tools/apktool so
# it can be inspected, replaced, or removed without touching the host system.

set -euo pipefail

_config_script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
REPO_ROOT="$(cd "${_config_script_dir}/../../../.." && pwd -P)"

DEFAULT_TOOL_DIR="${REPO_ROOT}/tools/apktool"
TOOL_DIR="${APKTOOL_HOME:-${DEFAULT_TOOL_DIR}}"
JAR_PATH="${TOOL_DIR}/apktool.jar"
VERSION_FILE="${TOOL_DIR}/VERSION"

RELEASES_API="https://api.github.com/repos/iBotPeaches/Apktool/releases/latest"
RELEASES_LATEST="https://github.com/iBotPeaches/Apktool/releases/latest"
DOWNLOAD_URL_TEMPLATE="https://github.com/iBotPeaches/Apktool/releases/download/v%s/apktool_%s.jar"

MIN_JAVA_MAJOR=8

log() {
    printf '[apktool] %s\n' "$*"
}

err() {
    printf '[apktool] ERROR: %s\n' "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# Print the Java feature version (8, 11, 17, 21, ...) or fail.
java_major() {
    local output version
    output="$(java -version 2>&1)" || return 1
    version="$(printf '%s\n' "${output}" | sed -n 's/.*version "\([^"]*\)".*/\1/p' | sed -n '1p')"
    [[ -n "${version}" ]] || return 1
    # Java 8 and older report "1.8.0_x".
    version="${version%%_*}"
    version="${version%%-*}"
    if [[ "${version}" == 1.* ]]; then
        printf '%s\n' "${version#1.}" | cut -d. -f1
    else
        printf '%s\n' "${version}" | cut -d. -f1
    fi
}

normalize_version() {
    printf '%s\n' "${1#v}"
}

# Compare two dotted versions with GNU sort -V.
version_ge() {
    local left="$1" right="$2"
    [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n 1)" == "${left}" ]]
}

# Print the version reported by an apktool jar, or fail.
jar_version() {
    local jar="$1" output
    [[ -f "${jar}" ]] || return 1
    have java || return 1
    output="$(java -jar "${jar}" --version 2>/dev/null | tr -d '\r' | tail -n 1)" || return 1
    [[ -n "${output}" ]] || return 1
    normalize_version "${output}"
}

# Resolve the latest upstream release tag, preferring the API and falling back
# to the redirect of /releases/latest when the API is rate limited.
latest_version() {
    local version=""
    if have curl; then
        version="$(curl -fsSL --max-time 20 "${RELEASES_API}" 2>/dev/null \
            | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' \
            | sed -n '1p')"
    fi
    if [[ -z "${version}" ]] && have curl; then
        version="$(curl -fsSIL --max-time 20 -o /dev/null -w '%{url_effective}' "${RELEASES_LATEST}" 2>/dev/null \
            | sed -n 's#.*/tag/v\{0,1\}\([^/]*\)$#\1#p')"
    fi
    [[ -n "${version}" ]] || return 1
    normalize_version "${version}"
}
