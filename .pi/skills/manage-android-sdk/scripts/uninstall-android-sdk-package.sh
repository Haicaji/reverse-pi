#!/usr/bin/env bash

# Uninstall SDK packages with sdkmanager --uninstall. Requires --confirm
# because package removal deletes files from the SDK directory.
#
# Exit codes:
#   0   packages removed
#   1   invalid argument, package not installed, or sdkmanager failure
#   10  SDK not configured / sdkmanager missing
#   11  JDK missing/too old

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: uninstall-android-sdk-package.sh --confirm [--sdk-root PATH] PACKAGE...

Removes SDK packages with `sdkmanager --uninstall`, e.g.:
  uninstall-android-sdk-package.sh --confirm "build-tools;36.0.0"

--confirm is required: deletion needs explicit user consent.
Command-line Tools themselves are never uninstalled by this Skill; to remove the
whole SDK, the user must delete the directory manually.
EOF
}

confirm=0
pkg_args=()

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
        --confirm)
            confirm=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            err "未知参数：$1"
            usage >&2
            exit 1
            ;;
        *)
            pkg_args+=("$1")
            ;;
    esac
    shift
done

if ((${#pkg_args[@]} == 0)); then
    err "未指定要卸载的组件"
    usage >&2
    exit 1
fi

if ((confirm == 0)); then
    err "拒绝执行：卸载组件会删除 SDK 文件"
    log "请先向用户确认，然后加 --confirm 重新执行"
    exit 1
fi

for pkg in "${pkg_args[@]}"; do
    if ! [[ "${pkg}" =~ ^[A-Za-z0-9._-]+(\;[A-Za-z0-9._-]+)*$ ]]; then
        err "无效的组件名：${pkg}"
        exit 1
    fi
    if [[ "${pkg}" == cmdline-tools\;* ]]; then
        err "本 Skill 不卸载 Command-line Tools（会破坏 sdkmanager）：${pkg}"
        exit 1
    fi
done

check_java || exit $?
resolve_sdk_root 1 || exit $?
log "SDK 根目录：${SDK_ROOT}（来源：${SDK_ROOT_SOURCE}）"
require_sdkmanager || exit $?

installed_output="$(list_installed_text)"
if [[ -z "${installed_output}" ]]; then
    err "无法读取已安装组件列表（sdkmanager --list_installed 失败）"
    exit 1
fi

for pkg in "${pkg_args[@]}"; do
    if ! package_present_in_list "${pkg}" "${installed_output}"; then
        err "该组件未安装：${pkg}"
        exit 1
    fi
done

log "将卸载：${pkg_args[*]}"
set +e
sdkmanager_run --uninstall "${pkg_args[@]}"
sdk_rc=$?
set -e
if ((sdk_rc != 0)) || sdkmanager_output_indicates_failure; then
    err "sdkmanager --uninstall 失败；日志：${LAST_SDKMANAGER_LOG}"
    ((sdk_rc != 0)) && log "退出码：${sdk_rc}"
    exit 1
fi

remaining_output="$(list_installed_text)"
for pkg in "${pkg_args[@]}"; do
    if package_present_in_list "${pkg}" "${remaining_output}"; then
        err "卸载后仍然检测到组件：${pkg}"
        exit 1
    fi
done

log "已卸载：${pkg_args[*]}"
