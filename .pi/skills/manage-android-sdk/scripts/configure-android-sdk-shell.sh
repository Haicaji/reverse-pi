#!/usr/bin/env bash

# Write the ANDROID_HOME/ANDROID_SDK_ROOT/PATH block into the user's shell rc
# file (~/.bashrc by default). Writing is the default behaviour: the SDK
# environment is meant to live in bashrc, not in a Pi-only shell wrapper.
# Use --print to only show the block without touching any file.
#
# Exit codes:
#   0   printed/written (or already up to date)
#   1   invalid argument, missing bashrc, or syntax check failed
#   10  SDK not configured
#   11  JDK missing/too old

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: configure-android-sdk-shell.sh [--sdk-root PATH] [options]

Writes a managed block into the shell rc file so that ANDROID_HOME,
ANDROID_SDK_ROOT and PATH are set for every new terminal:

  # >>> reverse-pi android-sdk >>>
  export ANDROID_HOME="/path/to/sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="...:$PATH"
  # <<< reverse-pi android-sdk <<<

Options:
  --sdk-root PATH     SDK directory (default: recorded path or env)
  --bashrc FILE       Shell rc file to update; default: ~/.bashrc
  --print             Only print the block, do not modify any file
  --replace-legacy    Comment out unmanaged ANDROID_HOME/ANDROID_SDK_ROOT/
                      PATH exports that would conflict with the block
  --no-replace-legacy Keep unmanaged Android exports untouched (default)
  --write             Accepted for compatibility; writing is now the default
  -h, --help          Show this help

Exit codes: 0 ok | 1 failure | 10 SDK missing | 11 JDK
EOF
}

bashrc="${ANDROID_SDK_BASHRC:-${HOME}/.bashrc}"
write=1
replace_legacy=0
out_file=""

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
        --bashrc)
            shift
            [[ $# -gt 0 ]] || { err "--bashrc 需要一个路径"; exit 1; }
            bashrc="$1"
            ;;
        --bashrc=*)
            bashrc="${1#*=}"
            ;;
        --print|--dry-run|--stdout)
            write=0
            ;;
        --replace-legacy)
            replace_legacy=1
            ;;
        --no-replace-legacy)
            replace_legacy=0
            ;;
        --write)
            write=1
            ;;
        --out)
            shift
            [[ $# -gt 0 ]] || { err "--out 需要一个路径"; exit 1; }
            out_file="$1"
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

if ((write)) && [[ "${bashrc}" != /* ]]; then
    err "--bashrc 需要绝对路径：${bashrc}"
    exit 1
fi

check_java || exit $?
resolve_sdk_root 1 || exit $?
require_sdkmanager || exit $?
log "SDK 根目录：${SDK_ROOT}（来源：${SDK_ROOT_SOURCE}）"

build_tools_version="$(latest_installed_build_tools || true)"
path_expr='$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools'
if [[ -n "${build_tools_version}" ]]; then
    path_expr="${path_expr}:\$ANDROID_HOME/build-tools/${build_tools_version}"
fi

make_block() {
    printf '%s\n' '# >>> reverse-pi android-sdk >>>'
    printf '%s\n' '# Managed by .pi/skills/manage-android-sdk (configure-android-sdk-shell.sh).'
    printf 'export ANDROID_HOME=%s\n' "$(shell_dquote "${SDK_ROOT}")"
    printf '%s\n' 'export ANDROID_SDK_ROOT="$ANDROID_HOME"'
    printf 'export PATH="%s:$PATH"\n' "${path_expr}"
    printf '%s\n' '# <<< reverse-pi android-sdk <<<'
}

if ((write == 0)); then
    if [[ -n "${out_file}" ]]; then
        make_block >"${out_file}"
        log "已写入 ${out_file}"
    else
        log "以下内容未写入任何文件（--print）："
        make_block
    fi
    exit 0
fi

if [[ ! -f "${bashrc}" ]]; then
    err "shell 配置文件不存在：${bashrc}"
    log "请用 --bashrc FILE 指定现有文件，或由用户自行创建"
    exit 1
fi

if ! have awk || ! have bash; then
    err "缺少 awk 或 bash，无法安全更新 ${bashrc}"
    exit 1
fi

tmp="${bashrc}.reverse-pi-android-sdk.$$"
cleanup_tmp() {
    rm -f "${tmp}"
}
trap cleanup_tmp EXIT

legacy_count="$(mktemp "${TMPDIR:-/tmp}/android-sdk-legacy.XXXXXX")"
trap 'cleanup_tmp; rm -f "${legacy_count}"' EXIT

# Drop a previously managed block, then optionally disable unmanaged Android
# exports that would override the freshly written block.
if ! awk -v replace="${replace_legacy}" -v countfile="${legacy_count}" '
    function is_android_line(line) {
        if (line ~ /^[[:space:]]*(export[[:space:]]+)?ANDROID_HOME=/) return 1
        if (line ~ /^[[:space:]]*(export[[:space:]]+)?ANDROID_SDK_ROOT=/) return 1
        if (line ~ /^[[:space:]]*export[[:space:]]+PATH=/ &&
            line ~ /ANDROID_(HOME|SDK_ROOT)/) return 1
        return 0
    }
    /^# >>> reverse-pi android-sdk >>>$/ { in_block = 1; next }
    /^# <<< reverse-pi android-sdk <<<$/ { in_block = 0; next }
    in_block { next }
    {
        if (replace == 1 && is_android_line($0)) {
            print "# [disabled by reverse-pi android-sdk] " $0
            replaced++
            next
        }
        print
    }
    END { printf "%d\n", replaced + 0 > countfile }
' "${bashrc}" >"${tmp}"; then
    err "读取 ${bashrc} 失败"
    exit 1
fi

disabled="$(cat "${legacy_count}" 2>/dev/null || printf '0')"

if [[ -s "${tmp}" ]] && [[ "$(tail -c 1 "${tmp}")" != "" ]]; then
    printf '\n' >>"${tmp}"
fi

make_block >>"${tmp}"

if ! bash -n "${tmp}"; then
    err "生成的 shell 配置语法检查失败，未修改 ${bashrc}"
    exit 1
fi

if cmp -s "${tmp}" "${bashrc}"; then
    log "${bashrc} 已是最新（ANDROID_HOME=${SDK_ROOT}）"
    exit 0
fi

backup="${bashrc}.bak.$(date +%Y%m%d-%H%M%S)-$$"
if ! cp -p "${bashrc}" "${backup}"; then
    err "备份失败：${backup}"
    exit 1
fi

mode="$(stat -c %a "${bashrc}")"
if ! mv "${tmp}" "${bashrc}"; then
    err "写入 ${bashrc} 失败"
    exit 1
fi
chmod "${mode}" "${bashrc}"

if ((disabled > 0)); then
    log "已注释掉 ${disabled} 行原有的 Android 环境变量配置"
fi
log "已更新 ${bashrc}（备份：${backup}）"
if ((replace_legacy == 0)) && grep -qE '^[[:space:]]*(export[[:space:]]+)?ANDROID_(HOME|SDK_ROOT)=' "${bashrc}"; then
    warn "仍存在未被本 Skill 管理的 ANDROID_HOME/ANDROID_SDK_ROOT 配置"
    log "它们可能在新的终端里覆盖托管块；需要时用 --replace-legacy 重新运行"
fi
log "执行 source ${bashrc} 或重新打开终端后生效"
