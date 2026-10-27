#!/usr/bin/env bash

# Print shell exports for the resolved Android SDK. Use with:
#   eval "$(env-android-sdk.sh --sdk-root /path/to/sdk)"
#
# Exit codes:
#   0   exports printed
#   1   invalid --sdk-root
#   10  no SDK root resolved

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: env-android-sdk.sh [--sdk-root PATH]

Prints (to stdout) the exports for the resolved SDK:

  export ANDROID_HOME='...'
  export ANDROID_SDK_ROOT='...'
  export PATH='...':"$PATH"

Diagnostics go to stderr, so `eval "$(env-android-sdk.sh ...)"` is safe.
EOF
}

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

resolve_sdk_root 1 || exit $?

path_prefix="${SDK_ROOT}/cmdline-tools/latest/bin"
[[ -d "${SDK_ROOT}/platform-tools" ]] && path_prefix="${path_prefix}:${SDK_ROOT}/platform-tools"

build_tools_version="$(latest_installed_build_tools || true)"
if [[ -n "${build_tools_version}" ]]; then
    path_prefix="${path_prefix}:${SDK_ROOT}/build-tools/${build_tools_version}"
fi

printf 'export ANDROID_HOME=%s\n' "$(shell_dquote "${SDK_ROOT}")"
printf 'export ANDROID_SDK_ROOT=%s\n' "$(shell_dquote "${SDK_ROOT}")"
# $PATH must stay expandable, so only the prefix is quoted/escaped here.
printf 'export PATH=%s:$PATH\n' "$(shell_dquote "${path_prefix}")"
