#!/usr/bin/env bash

# Install the Android SDK Command-line Tools plus SDK components at a
# user-chosen location. The SDK root is never assumed.
#
# Exit codes:
#   0   installed, or already up to date
#   1   invalid argument, repository/download failure, or sdkmanager error
#   10  no SDK root resolved (ask the user where to install)
#   11  JDK missing/too old, or sdkmanager cannot run
#   12  missing shell commands (curl/unzip/...)
#   13  license not accepted (needs --accept-licenses / user consent)
#   14  SDK directory not creatable/writable

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: install-android-sdk.sh --sdk-root PATH [options]

Downloads Google's official Command-line Tools, accepts the SDK licenses
(only with --accept-licenses) and installs SDK components into PATH.

Options:
  --sdk-root PATH          SDK directory chosen by the user (required the first
                           time; later runs reuse ANDROID_HOME from the managed
                           block in the shell rc file)
  --build-tools VERSION    Build Tools version, "latest" (default) or "none"
  --platform API           Install platforms;android-API ("latest" or "none";
                           default: none, not needed for APK inspection)
  --components "PKG ..."   Extra packages, e.g. "cmdline-tools;23.0 emulator"
  --accept-licenses        Feed "y" to `sdkmanager --licenses` (needs user consent)
  --bashrc FILE            Shell rc file updated after install; default: ~/.bashrc
  --replace-legacy         Comment out unmanaged ANDROID_HOME/ANDROID_SDK_ROOT/
                           PATH exports while updating the rc file
  --no-write-shell         Do not touch the shell rc file (no record is kept)
  --skip-cmdline-tools     Do not download/replace the Command-line Tools
  --skip-packages          Only set up the Command-line Tools
  --skip-platform-tools    Do not install platform-tools (adb)
  --force                  Reinstall Command-line Tools even when current
  --dry-run                Print planned actions without writing to the SDK dir

After a successful install the ANDROID_HOME/ANDROID_SDK_ROOT/PATH block is
written into the shell rc file (default ~/.bashrc), so no Pi-specific
environment is needed.

Exit codes:
  0 ok | 1 failure | 10 path unknown | 11 JDK | 12 commands
  13 licenses | 14 directory not writable
EOF
}

build_tools_req="latest"
platform_req="none"
components_raw=""
accept=0
skip_cmdline=0
skip_packages=0
skip_platform_tools=0
force=0
dry_run=0
write_shell=1
replace_legacy=0
bashrc="${ANDROID_SDK_BASHRC:-${HOME}/.bashrc}"

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
        --build-tools)
            shift
            [[ $# -gt 0 ]] || { err "--build-tools 需要一个值"; exit 1; }
            build_tools_req="$1"
            ;;
        --build-tools=*)
            build_tools_req="${1#*=}"
            ;;
        --platform)
            shift
            [[ $# -gt 0 ]] || { err "--platform 需要一个值"; exit 1; }
            platform_req="$1"
            ;;
        --platform=*)
            platform_req="${1#*=}"
            ;;
        --components)
            shift
            [[ $# -gt 0 ]] || { err "--components 需要一个值"; exit 1; }
            components_raw="$1"
            ;;
        --components=*)
            components_raw="${1#*=}"
            ;;
        --accept-licenses)
            accept=1
            ;;
        --skip-cmdline-tools)
            skip_cmdline=1
            ;;
        --skip-packages)
            skip_packages=1
            ;;
        --skip-platform-tools)
            skip_platform_tools=1
            ;;
        --force|-f)
            force=1
            ;;
        --dry-run)
            dry_run=1
            ;;
        --bashrc)
            shift
            [[ $# -gt 0 ]] || { err "--bashrc 需要一个路径"; exit 1; }
            bashrc="$1"
            ;;
        --bashrc=*)
            bashrc="${1#*=}"
            ;;
        --replace-legacy)
            replace_legacy=1
            ;;
        --no-write-shell)
            write_shell=0
            ;;
        --write-shell)
            write_shell=1
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

if [[ "${bashrc}" != /* ]]; then
    err "--bashrc 需要绝对路径：${bashrc}"
    exit 1
fi

case "${build_tools_req}" in
    none|latest) ;;
    *)
        if ! [[ "${build_tools_req}" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
            err "无效的 --build-tools：${build_tools_req}（使用 latest、none 或 x.y.z）"
            exit 1
        fi
        ;;
esac

case "${platform_req}" in
    none|latest|android-[0-9]*|[0-9]*|"") ;;
    *)
        err "无效的 --platform：${platform_req}（使用 latest、none、36 或 android-36）"
        exit 1
        ;;
esac

TMP_DIR=""
REPO_XML=""
cleanup() {
    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi
    [[ -n "${REPO_XML}" ]] && rm -f "${REPO_XML}"
}
trap cleanup EXIT

human_size() {
    local size="$1"
    if [[ "${size}" =~ ^[0-9]+$ ]] && ((size > 0)); then
        printf '%d MB' "$((size / 1048576))"
    else
        printf 'unknown'
    fi
}

install_cmdline_tools() {
    local revision="$1" url="$2" sha1="$3"
    local dest src actual backup

    dest="${SDK_ROOT}/${CMDLINE_TOOLS_REL_DIR}"
    mkdir -p "${SDK_ROOT}/cmdline-tools"
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/android-sdk.XXXXXX")"

    log "下载 Command-line Tools ${revision}（$(human_size "${4:-0}")）：${url}"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 1800 \
        -o "${TMP_DIR}/cmdline-tools.zip" "${url}"; then
        err "下载失败：${url}"
        return 1
    fi

    actual="$(sha1sum "${TMP_DIR}/cmdline-tools.zip" | awk '{print $1}')"
    if [[ "${actual}" != "${sha1}" ]]; then
        err "SHA-1 校验失败：期望 ${sha1}，实际 ${actual}"
        return 1
    fi
    log "SHA-1 校验通过"

    if ! unzip -q "${TMP_DIR}/cmdline-tools.zip" -d "${TMP_DIR}/extract"; then
        err "解压失败：${TMP_DIR}/cmdline-tools.zip"
        return 1
    fi
    src="${TMP_DIR}/extract/cmdline-tools"
    if [[ ! -x "${src}/bin/sdkmanager" ]]; then
        src="${TMP_DIR}/extract"
    fi
    if [[ ! -x "${src}/bin/sdkmanager" ]]; then
        err "压缩包结构异常：未找到 bin/sdkmanager"
        return 1
    fi

    if [[ -e "${dest}" ]]; then
        backup="${dest}.bak.$(date +%Y%m%d-%H%M%S)-$$"
        log "备份现有 Command-line Tools：${backup}"
        mv "${dest}" "${backup}"
    fi
    mkdir -p "${dest}"
    if ! cp -a "${src}/." "${dest}/"; then
        err "复制 Command-line Tools 到 ${dest} 失败"
        return 1
    fi

    if ! "${dest}/bin/sdkmanager" --version >/dev/null 2>&1; then
        err "sdkmanager 无法运行（可能与当前 Java 版本不兼容）"
        return 11
    fi
    log "已安装 Command-line Tools ${revision}：${dest}"
    return 0
}

# Resolve a build-tools package from the repository index; empty when "none".
resolve_build_tools() {
    local xml="$1" version
    [[ "${build_tools_req}" == "none" ]] && return 0
    if [[ "${build_tools_req}" == "latest" ]]; then
        if ! version="$(latest_build_tools "${xml}")"; then
            err "无法从仓库索引解析最新 build-tools 版本"
            return 1
        fi
        log "最新稳定 build-tools：${version}"
    else
        version="${build_tools_req}"
    fi
    if ! package_available "${xml}" "build-tools;${version}"; then
        err "仓库索引中没有 build-tools;${version}"
        return 1
    fi
    printf '%s\n' "build-tools;${version}"
}

# Resolve a platforms package; empty when "none".
resolve_platform() {
    local xml="$1" api
    [[ "${platform_req}" == "none" || -z "${platform_req}" ]] && return 0
    if [[ "${platform_req}" == "latest" ]]; then
        if ! api="$(latest_platform "${xml}")"; then
            err "无法从仓库索引解析最新 platform"
            return 1
        fi
        log "最新稳定 platform：${api}"
    elif [[ "${platform_req}" == android-* ]]; then
        api="${platform_req}"
    else
        api="android-${platform_req}"
    fi
    if ! package_available "${xml}" "platforms;${api}"; then
        err "仓库索引中没有 platforms;${api}"
        return 1
    fi
    printf '%s\n' "platforms;${api}"
}

packages=()

add_package() {
    local pkg="$1" existing
    ((${#packages[@]} > 0)) || {
        packages+=("${pkg}")
        return 0
    }
    for existing in "${packages[@]}"; do
        [[ "${existing}" == "${pkg}" ]] && return 0
    done
    packages+=("${pkg}")
}

verify_tools() {
    local failures=0 pkg bt_dir tool installed_text=""
    ((${#packages[@]} > 0)) || return 0
    if [[ -n "${SDKMANAGER}" && -x "${SDKMANAGER}" ]]; then
        installed_text="$(list_installed_text)"
    fi
    for pkg in "${packages[@]}"; do
        if [[ -n "${installed_text}" ]] && ! package_present_in_list "${pkg}" "${installed_text}"; then
            warn "sdkmanager 未报告已安装：${pkg}"
            failures=1
            continue
        fi
        case "${pkg}" in
            platform-tools)
                if [[ -x "${SDK_ROOT}/platform-tools/adb" ]]; then
                    log "adb：${SDK_ROOT}/platform-tools/adb"
                else
                    warn "platform-tools 已安装，但找不到 ${SDK_ROOT}/platform-tools/adb"
                    failures=1
                fi
                ;;
            build-tools\;*)
                bt_dir="${SDK_ROOT}/build-tools/${pkg#build-tools;}"
                for tool in aapt aapt2 apksigner zipalign; do
                    if [[ -x "${bt_dir}/${tool}" ]]; then
                        log "${tool}：${bt_dir}/${tool}"
                    else
                        warn "缺少 ${bt_dir}/${tool}"
                        failures=1
                    fi
                done
                ;;
        esac
    done
    return $((failures > 0 ? 1 : 0))
}

log "步骤 1/7：检查运行环境"
check_java || exit $?
require_install_tools || exit $?

log "步骤 2/7：确定 SDK 目录"
resolve_sdk_root 1 || exit $?
log "SDK 根目录：${SDK_ROOT}（来源：${SDK_ROOT_SOURCE}）"
if ((dry_run == 0)); then
    prepare_sdk_root "${SDK_ROOT}" || exit $?
else
    log "DRY RUN：跳过目录创建与写入"
fi
SDKMANAGER="$(sdkmanager_path)"

log "步骤 3/7：读取 Google 仓库索引"
need_index=0
((skip_cmdline)) || need_index=1
[[ "${build_tools_req}" != "none" && ${skip_packages} -eq 0 ]] && need_index=1
[[ "${platform_req}" != "none" && ${skip_packages} -eq 0 ]] && need_index=1
if ((need_index)); then
    REPO_XML="$(fetch_repo_xml)" || exit 1
else
    log "跳过（无需仓库索引）"
fi

log "步骤 4/7：安装 Command-line Tools"
if ((skip_cmdline)); then
    log "跳过（--skip-cmdline-tools）"
else
    info="$(cmdline_tools_release_info "${REPO_XML}")" || exit 1
    IFS=$'\t' read -r ct_revision ct_size ct_sha1 ct_url <<<"${info}"
    log "上游最新 Command-line Tools：${ct_revision}（$(human_size "${ct_size}")）"

    current_revision="$(installed_cmdline_tools_revision || true)"
    if [[ "${current_revision}" == "${ct_revision}" && ${force} -eq 0 ]]; then
        log "已安装 ${current_revision}，无需下载（--force 可强制重装）"
    elif ((dry_run)); then
        log "将下载：${ct_url}"
        log "将校验：SHA-1 ${ct_sha1}"
        log "将安装到：${SDK_ROOT}/${CMDLINE_TOOLS_REL_DIR}"
    else
        install_cmdline_tools "${ct_revision}" "${ct_url}" "${ct_sha1}" "${ct_size}" || exit $?
    fi
fi

log "步骤 5/7：接受 SDK 许可证"
if ((skip_packages)); then
    log "跳过（--skip-packages）"
elif ((dry_run)); then
    if ((accept)); then
        log "将执行：$(sdkmanager_path) --sdk_root=${SDK_ROOT} --licenses"
    else
        log "未指定 --accept-licenses，将跳过许可证步骤"
    fi
else
    require_sdkmanager || exit $?
    if ((accept)); then
        accept_licenses || exit 1
    else
        warn "未指定 --accept-licenses，跳过许可证步骤"
        log "安装组件可能因许可证未接受而失败；取得用户同意后加 --accept-licenses 重试"
    fi
fi

log "步骤 6/7：安装 SDK 组件"
if ((skip_packages)); then
    log "跳过（--skip-packages）"
else
    build_tools_pkg="$(resolve_build_tools "${REPO_XML}")" || exit 1
    [[ -n "${build_tools_pkg}" ]] && add_package "${build_tools_pkg}"

    platform_pkg="$(resolve_platform "${REPO_XML}")" || exit 1
    [[ -n "${platform_pkg}" ]] && add_package "${platform_pkg}"

    ((skip_platform_tools)) || add_package "platform-tools"

    if [[ -n "${components_raw}" ]]; then
        components_raw="${components_raw//,/ }"
        read -r -a extra_components <<<"${components_raw}"
        for pkg in "${extra_components[@]}"; do
            if ! [[ "${pkg}" =~ ^[A-Za-z0-9._-]+(\;[A-Za-z0-9._-]+)*$ ]]; then
                err "无效的组件名：${pkg}"
                exit 1
            fi
            add_package "${pkg}"
        done
    fi

    if ((${#packages[@]} == 0)); then
        log "没有需要安装的组件"
    elif ((dry_run)); then
        log "将执行：${SDKMANAGER} --sdk_root=${SDK_ROOT} ${packages[*]}"
    else
        log "安装组件：${packages[*]}"
        set +e
        sdkmanager_run "${packages[@]}"
        sdk_rc=$?
        set -e
        if ((sdk_rc != 0)) || sdkmanager_output_indicates_failure; then
            if [[ -n "${LAST_SDKMANAGER_LOG}" ]] && grep -qi 'licen[cs]e' "${LAST_SDKMANAGER_LOG}"; then
                err "安装失败：SDK 许可证未接受"
                log "与用户确认后加 --accept-licenses 重试"
                exit 13
            fi
            err "sdkmanager 安装失败；日志：${LAST_SDKMANAGER_LOG}"
            ((sdk_rc != 0)) && log "退出码：${sdk_rc}"
            exit 1
        fi
    fi
fi

log "步骤 7/7：验证并写入 shell 配置"
if ((dry_run)); then
    if ((write_shell)); then
        log "将更新 shell 配置：${bashrc}（ANDROID_HOME=${SDK_ROOT}）"
    else
        log "将跳过 shell 配置（--no-write-shell）"
    fi
    log "DRY RUN：未做任何修改"
    exit 0
fi

if [[ -x "${SDKMANAGER}" ]] && ! "${SDKMANAGER}" --version >/dev/null 2>&1; then
    err "sdkmanager 无法运行，请检查 Java 版本"
    exit 11
fi

verify_ok=0
verify_tools || verify_ok=$?
log "Android SDK 准备完成：${SDK_ROOT}"

shell_ok=0
if ((write_shell)); then
    log "写入 shell 配置：${bashrc}"
    shell_args=(--sdk-root "${SDK_ROOT}" --bashrc "${bashrc}")
    ((replace_legacy)) && shell_args+=(--replace-legacy)
    if ! "${script_dir}/configure-android-sdk-shell.sh" "${shell_args[@]}"; then
        warn "写入 ${bashrc} 失败；SDK 已安装，可稍后手动运行 configure-android-sdk-shell.sh"
        shell_ok=1
    fi
else
    log "跳过 shell 配置（--no-write-shell）"
    printf '[android-sdk] 需要时写入 shell 配置：\n'
    printf '  %s/configure-android-sdk-shell.sh --sdk-root %s\n' "${script_dir}" "$(printf '%q' "${SDK_ROOT}")"
fi

((verify_ok == 0)) || exit 1
((shell_ok == 0)) || exit 1
exit 0
