#!/usr/bin/env bash

# Download and install apktool into <repo>/tools/apktool.
#
# Exit codes:
#   0  installed or already up to date
#   11 Java is missing/too old
#   1  download or validation failed

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: install-apktool.sh [--version VERSION] [--force]

Downloads the apktool release jar from GitHub, validates it, and installs:
  - tools/apktool/apktool.jar
  - tools/apktool/VERSION

Invoke it with: java -jar tools/apktool/apktool.jar

Options:
  --version VERSION  Install a specific release (default: latest)
  --force            Reinstall even when the same version is present
EOF
}

version=""
force=0

while (($# > 0)); do
    case "$1" in
        --version|-v)
            shift
            [[ $# -gt 0 ]] || { err "--version requires a value"; exit 1; }
            version="$1"
            ;;
        --version=*)
            version="${1#*=}"
            ;;
        --force|-f)
            force=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "unknown argument: $1"
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if ! have java; then
    err "java not found; apktool requires Java ${MIN_JAVA_MAJOR}+. Install a JDK and retry."
    exit 11
fi

java_version="$(java_major || true)"
if [[ -z "${java_version}" ]]; then
    err "unable to determine the Java version"
    exit 11
fi
if ((java_version < MIN_JAVA_MAJOR)); then
    err "Java ${java_version} is too old; apktool requires Java ${MIN_JAVA_MAJOR}+"
    exit 11
fi

if ! have curl; then
    err "curl is required to download apktool"
    exit 1
fi

version="$(normalize_version "${version}")"
if [[ -z "${version}" ]]; then
    version="$(latest_version || true)"
    if [[ -z "${version}" ]]; then
        err "failed to query the latest apktool release from GitHub"
        exit 1
    fi
fi

if ! [[ "${version}" =~ ^[0-9][0-9A-Za-z._-]*$ ]]; then
    err "invalid version: ${version}"
    exit 1
fi

current_version="$(jar_version "${JAR_PATH}" || true)"
if [[ "${current_version}" == "${version}" && ${force} -eq 0 ]]; then
    log "apktool ${version} is already installed"
    printf '[apktool] jar: %s\n' "${JAR_PATH}"
    exit 0
fi

mkdir -p "${TOOL_DIR}"

tmp_jar="${JAR_PATH}.tmp.$$"
cleanup() {
    rm -f "${tmp_jar}"
}
trap cleanup EXIT

url="${DOWNLOAD_URL_TEMPLATE//%s/${version}}"
log "downloading apktool ${version}"
log "  ${url}"
if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 300 -o "${tmp_jar}" "${url}"; then
    err "failed to download ${url}"
    exit 1
fi

downloaded_version="$(jar_version "${tmp_jar}" || true)"
if [[ "${downloaded_version}" != "${version}" ]]; then
    err "downloaded jar reports version '${downloaded_version:-unknown}', expected ${version}"
    exit 1
fi

mv -f "${tmp_jar}" "${JAR_PATH}"
printf '%s\n' "${version}" >"${VERSION_FILE}"

installed_version="$(jar_version "${JAR_PATH}" || true)"
if [[ "${installed_version}" != "${version}" ]]; then
    err "installed jar reports '${installed_version:-unknown}', expected ${version}"
    exit 1
fi

log "installed apktool ${version}"
printf '[apktool] jar: %s\n' "${JAR_PATH}"
printf '[apktool] invoke: java -jar %s\n' "${JAR_PATH}"
exit 0
