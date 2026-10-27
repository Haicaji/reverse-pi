#!/usr/bin/env bash

# Compare the repo-local apktool with the latest GitHub release.
#
# Exit codes:
#   0  up to date (or newer than the latest release)
#   20 update available
#   10 apktool is not installed under tools/apktool
#   1  the upstream release could not be queried

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: check-update-apktool.sh

Compares the installed apktool with the latest GitHub release.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        err "unknown argument: $1"
        usage >&2
        exit 1
        ;;
esac

current_version="$(jar_version "${JAR_PATH}" || true)"
if [[ -z "${current_version}" ]]; then
    err "apktool is not installed at ${JAR_PATH}"
    log "install with: ${script_dir}/install-apktool.sh"
    exit 10
fi

latest="$(latest_version || true)"
if [[ -z "${latest}" ]]; then
    err "failed to query the latest apktool release from GitHub"
    exit 1
fi

if [[ "${current_version}" == "${latest}" ]]; then
    log "apktool ${current_version} is up to date"
    exit 0
fi

if version_ge "${current_version}" "${latest}"; then
    log "installed apktool ${current_version} is newer than the latest release ${latest}"
    exit 0
fi

log "update available: ${current_version} -> ${latest}"
log "run: ${script_dir}/install-apktool.sh"
exit 20
