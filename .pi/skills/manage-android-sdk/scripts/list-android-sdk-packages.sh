#!/usr/bin/env bash

# List installed or available SDK packages through sdkmanager.
#
# Exit codes:
#   0   list printed
#   1   sdkmanager failed
#   10  SDK not configured / sdkmanager missing

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: list-android-sdk-packages.sh [--sdk-root PATH] [--all]

  (default)   installed packages only: sdkmanager --list_installed
  --all       installed and available packages: sdkmanager --list
EOF
}

all=0
while (($# > 0)); do
    case "$1" in
        --sdk-root)
            shift
            [[ $# -gt 0 ]] || { err "--sdk-root 需要一个路径"; exit 1; }
            SDK_ROOT_ARG="$1"
            ;;
        --sdk-root=*)
            SDK_ROOT_ARG="${1#*=}"
            ;;
        --all|-a)
            all=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "未知参数：$1"
            usage >&2
            exit 1
            ;;
    esac
    shift
done

check_java || exit $?
resolve_sdk_root 1 || exit $?
require_sdkmanager || exit $?

if ((all)); then
    exec "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --list
fi

set +e
"${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --list_installed
rc=$?
set -e
if ((rc != 0)); then
    warn "sdkmanager 不支持 --list_installed，回退到 --list"
    exec "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --list
fi
