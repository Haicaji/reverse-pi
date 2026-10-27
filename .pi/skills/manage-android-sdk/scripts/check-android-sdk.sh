#!/usr/bin/env bash

# Inspect the Android SDK installation: JDK, sdkmanager and the APK toolchain.
#
# Exit codes:
#   0   SDK usable and all core tools present
#   1   SDK found but some components/tools are missing
#   10  SDK not configured/installed (or path unresolved)
#   11  JDK missing or too old

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: check-android-sdk.sh [--sdk-root PATH]

Checks the JDK, resolves the SDK root and reports versions of
sdkmanager, adb, aapt, aapt2, apksigner and zipalign.

The SDK root comes from --sdk-root, then ANDROID_HOME in the managed block of
~/.bashrc, then a valid ANDROID_SDK_ROOT/ANDROID_HOME variable.

Exit codes:
  0   SDK usable, all core tools present
  1   SDK found but components missing (platform-tools/build-tools)
  10  SDK not configured or not installed
  11  JDK missing or too old
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

check_java || exit $?

resolve_sdk_root 1 || exit $?
log "SDK 根目录：${SDK_ROOT}（来源：${SDK_ROOT_SOURCE}）"

if ! require_sdkmanager; then
    log "目录存在，但 ./cmdline-tools/latest 不可用"
    exit 10
fi

cmdline_revision="$(installed_cmdline_tools_revision || true)"
sdkmanager_version="$("${SDKMANAGER}" --version 2>/dev/null | tr -d '\r' | head -n 1 || true)"
if [[ -z "${sdkmanager_version}" ]]; then
    err "sdkmanager 已存在但无法运行（Java 版本不兼容？）"
    printf '[android-sdk] sdkmanager: %s（不可用）\n' "${SDKMANAGER}"
    exit 11
fi
printf '[android-sdk] cmdline-tools: %s（sdkmanager %s）\n' \
    "${cmdline_revision:-unknown}" "${sdkmanager_version}"
printf '[android-sdk] sdkmanager: %s\n' "${SDKMANAGER}"

# first_line PATH [args...]: run the tool and print a short version line.
first_line() {
    local tool="$1"
    shift
    "${tool}" "$@" 2>&1 | tr -d '\r' | sed '/^[[:space:]]*$/d' | head -n 1
}

missing=()

# ---- platform-tools: adb ---------------------------------------------------
adb_path="${SDK_ROOT}/platform-tools/adb"
if [[ -x "${adb_path}" ]]; then
    adb_version="$(first_line "${adb_path}" version || true)"
    adb_version="$(printf '%s\n' "${adb_version}" | sed 's/^Android Debug Bridge version //')"
    printf '[android-sdk] adb: %s（%s）\n' "${adb_version:-unknown}" "${adb_path}"
elif command -v adb >/dev/null 2>&1; then
    adb_version="$(first_line "$(command -v adb)" version || true)"
    adb_version="$(printf '%s\n' "${adb_version}" | sed 's/^Android Debug Bridge version //')"
    warn "SDK 目录中没有 adb，使用的是 PATH 中的版本"
    printf '[android-sdk] adb: %s（%s）\n' "${adb_version:-unknown}" "$(command -v adb)"
    missing+=("platform-tools/adb")
else
    warn "未找到 adb（platform-tools 未安装）"
    missing+=("adb")
fi

# ---- build-tools: aapt, aapt2, apksigner, zipalign -------------------------
build_tools_version="$(latest_installed_build_tools || true)"
if [[ -z "${build_tools_version}" ]]; then
    warn "未找到 build-tools 目录"
    missing+=("build-tools")
else
    bt_dir="${SDK_ROOT}/build-tools/${build_tools_version}"
    printf '[android-sdk] build-tools: %s（%s）\n' "${build_tools_version}" "${bt_dir}"
    for tool in aapt aapt2 apksigner zipalign; do
        if [[ -x "${bt_dir}/${tool}" ]]; then
            case "${tool}" in
                apksigner) tool_version="$(first_line "${bt_dir}/${tool}" --version || true)" ;;
                zipalign) tool_version="$(first_line "${bt_dir}/${tool}" 2>&1 || true)" ;;
                *) tool_version="$(first_line "${bt_dir}/${tool}" version || true)" ;;
            esac
            printf '[android-sdk] %-10s %s（%s）\n' "${tool}:" "${tool_version:-ok}" "${bt_dir}/${tool}"
        else
            warn "build-tools ${build_tools_version} 中缺少 ${tool}"
            missing+=("${tool}")
        fi
    done
fi

if ((${#missing[@]} > 0)); then
    printf '[android-sdk] 缺少：%s\n' "${missing[*]}"
    log "状态：组件不完整；可用 install-android-sdk.sh 补齐"
    exit 1
fi

log "状态：正常（adb、aapt、aapt2、apksigner、zipalign 均可用）"
exit 0
