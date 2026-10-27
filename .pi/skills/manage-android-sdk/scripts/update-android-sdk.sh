#!/usr/bin/env bash

# Update an existing Android SDK: Command-line Tools from Google's repository
# index and installed SDK packages via `sdkmanager --update`.
#
# Exit codes:
#   0   update finished (verification may still report 1 for missing parts)
#   1   update failed / invalid argument
#   10  SDK not configured (or Command-line Tools missing)
#   11  JDK missing/too old, or sdkmanager cannot run
#   13  license not accepted (needs --accept-licenses / user consent)

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: update-android-sdk.sh [--sdk-root PATH] [options]

Updates the Command-line Tools (re-downloaded when Google publishes a newer
release) and runs `sdkmanager --update` for installed SDK packages.

Options:
  --sdk-root PATH        SDK directory (default: recorded path or env)
  --accept-licenses      Feed "y" to `sdkmanager --licenses` (needs user consent)
  --cmdline-tools-only   Only update Command-line Tools
  --packages-only        Only run `sdkmanager --update`
  --bashrc FILE          Shell rc file refreshed after the update; default ~/.bashrc
  --replace-legacy       Comment out unmanaged ANDROID_HOME/ANDROID_SDK_ROOT exports
  --no-write-shell       Do not touch the shell rc file
  --refresh              Ignore the cached repository index
  --dry-run              Print planned actions without changing anything

Exit codes: 0 ok | 1 failure | 10 SDK missing | 11 JDK | 13 licenses
EOF
}

accept=0
cmdline_tools_only=0
packages_only=0
refresh=0
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
        --accept-licenses)
            accept=1
            ;;
        --cmdline-tools-only)
            cmdline_tools_only=1
            ;;
        --packages-only)
            packages_only=1
            ;;
        --refresh)
            refresh=1
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

if ((cmdline_tools_only && packages_only)); then
    err "--cmdline-tools-only 与 --packages-only 不能同时使用"
    exit 1
fi

check_java || exit $?
resolve_sdk_root 1 || exit $?
log "SDK 根目录：${SDK_ROOT}（来源：${SDK_ROOT_SOURCE}）"
require_sdkmanager || exit $?

if ((packages_only == 0)); then
    log "步骤 1/4：检查 Command-line Tools 更新"
    REPO_XML="$(fetch_repo_xml "${refresh}")" || exit 1
    info="$(cmdline_tools_release_info "${REPO_XML}")" || exit 1
    IFS=$'\t' read -r latest_revision _latest_size _latest_sha1 _latest_url <<<"${info}"
    current_revision="$(installed_cmdline_tools_revision || true)"

    if [[ -n "${current_revision}" ]] && version_ge "${current_revision}" "${latest_revision}"; then
        log "Command-line Tools 已是最新：${current_revision}（上游 ${latest_revision}）"
    else
        log "Command-line Tools 可更新：${current_revision:-unknown} -> ${latest_revision}"
        if ((dry_run)); then
            log "将运行：install-android-sdk.sh --sdk-root ${SDK_ROOT} --skip-packages"
        else
            args=(--sdk-root "${SDK_ROOT}" --skip-packages --no-write-shell)
            ((refresh)) && args+=(--refresh)
            if ! "${script_dir}/install-android-sdk.sh" "${args[@]}"; then
                err "Command-line Tools 更新失败"
                exit 1
            fi
            require_sdkmanager || exit $?
        fi
    fi
fi

if ((cmdline_tools_only == 0)); then
    log "步骤 2/4：更新已安装的 SDK 组件"
    if ((accept)); then
        if ((dry_run)); then
            log "将执行：${SDKMANAGER} --sdk_root=${SDK_ROOT} --licenses"
        else
            accept_licenses || exit 1
        fi
    fi
    if ((dry_run)); then
        log "将执行：${SDKMANAGER} --sdk_root=${SDK_ROOT} --update"
    else
        set +e
        sdkmanager_run --update
        sdk_rc=$?
        set -e
        if ((sdk_rc != 0)) || sdkmanager_output_indicates_failure; then
            if [[ -n "${LAST_SDKMANAGER_LOG}" ]] && grep -qi 'licen[cs]e' "${LAST_SDKMANAGER_LOG}"; then
                err "更新失败：SDK 许可证未接受"
                log "与用户确认后加 --accept-licenses 重试"
                exit 13
            fi
            err "sdkmanager --update 失败；日志：${LAST_SDKMANAGER_LOG}"
            ((sdk_rc != 0)) && log "退出码：${sdk_rc}"
            exit 1
        fi
    fi
fi

if ((dry_run)); then
    log "DRY RUN：未做任何修改"
    exit 0
fi

log "步骤 3/4：验证安装结果"
check_rc=0
"${script_dir}/check-android-sdk.sh" --sdk-root "${SDK_ROOT}" || check_rc=$?
if ((check_rc != 0)); then
    warn "验证未完全通过（check-android-sdk.sh 退出码 ${check_rc}）"
fi

if ((write_shell)); then
    log "步骤 4/4：刷新 shell 配置 ${bashrc}"
    shell_args=(--sdk-root "${SDK_ROOT}" --bashrc "${bashrc}")
    ((replace_legacy)) && shell_args+=(--replace-legacy)
    if ! "${script_dir}/configure-android-sdk-shell.sh" "${shell_args[@]}"; then
        warn "刷新 ${bashrc} 失败（SDK 本身已完成更新）"
    fi
else
    log "步骤 4/4：跳过 shell 配置（--no-write-shell）"
fi

exit "${check_rc}"
