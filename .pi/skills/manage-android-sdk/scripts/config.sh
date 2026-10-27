#!/usr/bin/env bash

# Shared configuration and helpers for the manage-android-sdk Skill.
#
# Notes:
# - The SDK location is chosen by the user. This Skill never assumes
#   ~/Android/Sdk; the root comes from --sdk-root, the ANDROID_HOME value in
#   the managed shell-rc block, or an ANDROID_SDK_ROOT/ANDROID_HOME variable
#   that points to an existing dir.
# - No state directory is ever created: the only persistent record is the
#   managed block in the user's shell rc file. Temporary files (repository
#   index, sdkmanager output) live in ${TMPDIR:-/tmp} and are removed again.
# - Only Google's official repository index and downloads are used.
# - This Skill never installs a JDK and never uses sudo.

set -euo pipefail

# The shell rc file is the only place where state is written.
RC_FILE="${ANDROID_SDK_BASHRC:-${HOME}/.bashrc}"
RC_BEGIN_MARK="# >>> reverse-pi android-sdk >>>"
RC_END_MARK="# <<< reverse-pi android-sdk <<<"

REPO_XML_URL="${ANDROID_SDK_REPO_XML_URL:-https://dl.google.com/android/repository/repository2-3.xml}"

# Command-line Tools 20+ (repository2-3) need JDK 17. Override only when the
# user explicitly asks to try an older JDK.
MIN_JAVA_MAJOR="${ANDROID_SDK_MIN_JAVA:-17}"

CMDLINE_TOOLS_REL_DIR="cmdline-tools/latest"

SDK_ROOT_ARG="${SDK_ROOT_ARG:-}"
SDK_ROOT=""
SDK_ROOT_SOURCE=""
SDKMANAGER=""
LAST_SDKMANAGER_LOG=""

log() {
    # Diagnostics go to stderr so command substitutions only capture values.
    printf '[android-sdk] %s\n' "$*" >&2
}

warn() {
    printf '[android-sdk] WARNING: %s\n' "$*" >&2
}

err() {
    printf '[android-sdk] ERROR: %s\n' "$*" >&2
}

have() {
    command -v "$1" >/dev/null 2>&1
}

# Quote a value for a double-quoted shell string, so generated config always
# looks like ANDROID_HOME="/path/to/sdk" instead of a bare %q form.
shell_dquote() {
    local value="$1"
    value="$(printf '%s' "${value}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g')"
    printf '"%s"\n' "${value}"
}

# Print the Java feature version (8, 11, 17, 21, ...) or fail.
java_major() {
    local output version
    output="$(java -version 2>&1)" || return 1
    version="$(printf '%s\n' "${output}" | sed -n 's/.*version "\([^"]*\)".*/\1/p' | sed -n '1p')"
    [[ -n "${version}" ]] || return 1
    version="${version%%_*}"
    version="${version%%-*}"
    if [[ "${version}" == 1.* ]]; then
        printf '%s\n' "${version#1.}" | cut -d. -f1
    else
        printf '%s\n' "${version}" | cut -d. -f1
    fi
}

# Compare two dotted versions with GNU sort -V.
version_ge() {
    local left="$1" right="$2"
    [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | tail -n 1)" == "${left}" ]]
}

# Expand ~, make the path absolute and normalize it. Returns 1 for empty
# input, a bare "/" or anything that cannot be represented as an absolute path.
normalize_sdk_path() {
    local path="$1"
    [[ -n "${path}" ]] || return 1
    case "${path}" in
        "~") path="${HOME}" ;;
        "~/"*) path="${HOME}/${path#\~/}" ;;
    esac
    [[ "${path}" == /* ]] || path="${PWD}/${path}"
    if have realpath; then
        path="$(realpath -m -- "${path}")" || return 1
    fi
    [[ "${path}" == /* ]] || return 1
    [[ "${path}" != *$'\n'* ]] || return 1
    path="${path%/}"
    [[ -n "${path}" ]] || return 1
    printf '%s\n' "${path}"
}

# Read ANDROID_HOME from the managed block in the shell rc file. That block is
# the only record kept by this Skill; no separate state file exists.
persisted_root() {
    [[ -r "${RC_FILE}" ]] || return 1
    awk -v begin="${RC_BEGIN_MARK}" -v end="${RC_END_MARK}" '
        index($0, begin) { inblock = 1; next }
        index($0, end) { inblock = 0; next }
        inblock && /^export ANDROID_HOME=/ {
            value = $0
            sub(/^export ANDROID_HOME=/, "", value)
            gsub(/^"|"$/, "", value)
            print value
            exit
        }
    ' "${RC_FILE}"
}

# Resolve the SDK root into SDK_ROOT / SDK_ROOT_SOURCE.
#
# Exit codes:
#   0   resolved
#   1   --sdk-root is invalid
#   10  no usable path: ask the user where to install
resolve_sdk_root() {
    local allow_env="${1:-1}" candidate="" stored="" name="" value=""

    if [[ -n "${SDK_ROOT_ARG}" ]]; then
        if ! candidate="$(normalize_sdk_path "${SDK_ROOT_ARG}")"; then
            err "无效的 --sdk-root：${SDK_ROOT_ARG}"
            return 1
        fi
        SDK_ROOT_SOURCE="--sdk-root"
    fi

    if [[ -z "${candidate}" ]]; then
        stored="$(persisted_root || true)"
        if [[ -n "${stored}" ]]; then
            stored="$(normalize_sdk_path "${stored}" || true)"
            if [[ -n "${stored}" && -d "${stored}" ]]; then
                candidate="${stored}"
                SDK_ROOT_SOURCE="shell 配置 ${RC_FILE} 托管块"
            else
                warn "${RC_FILE} 托管块中的 SDK 路径不存在：${stored}（已忽略）"
            fi
        fi
    fi

    if [[ -z "${candidate}" && "${allow_env}" == "1" ]]; then
        for name in ANDROID_SDK_ROOT ANDROID_HOME; do
            value="${!name:-}"
            [[ -n "${value}" ]] || continue
            value="$(normalize_sdk_path "${value}" || true)"
            if [[ -n "${value}" && -d "${value}" ]]; then
                candidate="${value}"
                SDK_ROOT_SOURCE="${name} 环境变量"
                break
            fi
        done
    fi

    if [[ -z "${candidate}" ]]; then
        err "未确定 Android SDK 目录"
        for name in ANDROID_SDK_ROOT ANDROID_HOME; do
            value="${!name:-}"
            [[ -n "${value}" ]] || continue
            if [[ -d "${value}" ]]; then
                log "${name}=${value}（目录存在，但未采用；可用 --sdk-root 指定）"
            else
                log "${name}=${value}（目录不存在，已忽略）"
            fi
        done
        log "请询问用户希望把 SDK 安装到哪个目录，然后用 --sdk-root PATH 重试"
        return 10
    fi

    SDK_ROOT="${candidate}"
    return 0
}

# Create and validate the SDK root directory. Never escalates privileges.
prepare_sdk_root() {
    local root="$1" probe

    if [[ "${root}" == "/" || "${root}" == "${HOME%/}" ]]; then
        err "SDK 目录不能是 ${root}；请换一个专用目录"
        return 14
    fi
    if [[ -e "${root}" && ! -d "${root}" ]]; then
        err "SDK 路径已存在但不是目录：${root}"
        return 14
    fi
    if ! mkdir -p "${root}" 2>/dev/null; then
        err "无法创建 SDK 目录：${root}"
        log "权限不足时请由用户自行创建该目录；本 Skill 不使用 sudo"
        return 14
    fi
    probe="${root}/.reverse-pi-write-test.$$"
    if ! (: >"${probe}") 2>/dev/null; then
        err "SDK 目录不可写：${root}"
        return 14
    fi
    rm -f "${probe}"
    return 0
}

check_java() {
    local major
    if ! have java; then
        err "未找到 java；sdkmanager 需要 JDK ${MIN_JAVA_MAJOR}+"
        log "请用户安装 JDK 后重试；本 Skill 不会自行安装 JDK"
        return 11
    fi
    major="$(java_major || true)"
    if [[ -z "${major}" ]]; then
        err "无法解析 Java 版本（java -version 输出异常）"
        return 11
    fi
    if ((major < MIN_JAVA_MAJOR)); then
        err "Java 版本过低：${major}，需要 JDK ${MIN_JAVA_MAJOR}+"
        log "如需尝试更低版本，可由用户显式设置 ANDROID_SDK_MIN_JAVA 后重试"
        return 11
    fi
    log "Java：$(command -v java)（${major}）"
    return 0
}

# Commands required to download and unpack Command-line Tools.
require_install_tools() {
    local missing=() tool
    for tool in curl unzip sha1sum mktemp awk sed grep sort tee yes; do
        have "${tool}" || missing+=("${tool}")
    done
    if ((${#missing[@]} > 0)); then
        err "缺少命令：${missing[*]}"
        log "请用户先准备这些基础命令；本 Skill 不会自行安装系统依赖"
        return 12
    fi
    return 0
}

sdkmanager_path() {
    printf '%s\n' "${SDK_ROOT}/${CMDLINE_TOOLS_REL_DIR}/bin/sdkmanager"
}

require_sdkmanager() {
    local path
    path="$(sdkmanager_path)"
    if [[ ! -x "${path}" ]]; then
        err "未找到可执行的 sdkmanager：${path}"
        log "该 SDK 目录尚未安装 Command-line Tools；先运行 install-android-sdk.sh"
        return 10
    fi
    SDKMANAGER="${path}"
    return 0
}

# Download Google's repository index into a temporary file and print its path.
# Nothing is cached on disk; the caller removes the file when done.
fetch_repo_xml() {
    local tmp

    tmp="$(mktemp "${TMPDIR:-/tmp}/android-sdk-repo.XXXXXX")" || {
        err "无法创建临时文件（mktemp）"
        return 1
    }
    log "下载 Android SDK 仓库索引：${REPO_XML_URL}"
    if ! curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 -o "${tmp}" "${REPO_XML_URL}"; then
        rm -f "${tmp}"
        err "无法下载仓库索引：${REPO_XML_URL}"
        return 1
    fi
    if ! grep -q '<remotePackage' "${tmp}"; then
        rm -f "${tmp}"
        err "仓库索引内容异常：${REPO_XML_URL}"
        return 1
    fi
    printf '%s\n' "${tmp}"
}

# Print the complete <remotePackage> block for a package path.
package_block() {
    local xml="$1" path="$2"
    awk -v want="path=\"${path}\"" '
        /<remotePackage / { inblock = 1; buf = $0; next }
        inblock { buf = buf "\n" $0 }
        inblock && /<\/remotePackage>/ {
            if (index(buf, want) > 0) { print buf; exit }
            inblock = 0; buf = ""
        }
    ' "${xml}"
}

# True when the package path exists in the repository index.
package_available() {
    local xml="$1" pkg="$2"
    grep -q "remotePackage path=\"${pkg}\"" "${xml}"
}

# Print "revision<TAB>size<TAB>sha1<TAB>url" for the Linux Command-line Tools.
cmdline_tools_release_info() {
    local xml="$1" block archive major minor micro revision url sha1 size base

    block="$(package_block "${xml}" "cmdline-tools;latest")"
    if [[ -z "${block}" ]]; then
        err "仓库索引中找不到 cmdline-tools;latest"
        return 1
    fi
    archive="$(printf '%s\n' "${block}" | awk -v RS='</archive>' '/<host-os>linux<\/host-os>/ { print; exit }')"
    if [[ -z "${archive}" ]]; then
        err "仓库索引中没有 Linux 版 Command-line Tools"
        return 1
    fi

    major="$(printf '%s\n' "${block}" | sed -n 's:.*<major>\([0-9][0-9]*\)</major>.*:\1:p' | head -n 1)"
    minor="$(printf '%s\n' "${block}" | sed -n 's:.*<minor>\([0-9][0-9]*\)</minor>.*:\1:p' | head -n 1)"
    micro="$(printf '%s\n' "${block}" | sed -n 's:.*<micro>\([0-9][0-9]*\)</micro>.*:\1:p' | head -n 1)"
    if [[ -z "${major}" ]]; then
        err "无法解析 Command-line Tools 版本号"
        return 1
    fi
    revision="${major}.${minor:-0}"
    [[ -n "${micro}" ]] && revision="${revision}.${micro}"

    url="$(printf '%s\n' "${archive}" | sed -n 's:.*<url>\([^<]*\)</url>.*:\1:p' | head -n 1)"
    sha1="$(printf '%s\n' "${archive}" | sed -n 's:.*<checksum type="sha1">\([0-9a-fA-F]*\)</checksum>.*:\1:p' | head -n 1 | tr 'A-F' 'a-f')"
    size="$(printf '%s\n' "${archive}" | sed -n 's:.*<size>\([0-9][0-9]*\)</size>.*:\1:p' | head -n 1)"

    if [[ -z "${url}" || -z "${sha1}" ]]; then
        err "无法解析 Command-line Tools 的下载地址或校验值"
        return 1
    fi
    if ! [[ "${sha1}" =~ ^[0-9a-f]{40}$ ]]; then
        err "Command-line Tools 校验值格式异常：${sha1}"
        return 1
    fi
    if [[ "${url}" != http* ]]; then
        base="${REPO_XML_URL%/*}/"
        url="${base}${url}"
    fi
    printf '%s\t%s\t%s\t%s\n' "${revision}" "${size}" "${sha1}" "${url}"
}

# Print the newest stable build-tools version in the repository index.
latest_build_tools() {
    local xml="$1" version
    version="$(grep -o 'remotePackage path="build-tools;[0-9][0-9.]*"' "${xml}" \
        | sed 's/.*build-tools;\([0-9][0-9.]*\)".*/\1/' \
        | sort -V | tail -n 1)"
    [[ -n "${version}" ]] || return 1
    printf '%s\n' "${version}"
}

# Print the newest stable platform (android-XX) in the repository index.
latest_platform() {
    local xml="$1" platform
    platform="$(grep -o 'remotePackage path="platforms;android-[0-9][0-9]*"' "${xml}" \
        | sed 's/.*platforms;\(android-[0-9][0-9]*\)".*/\1/' \
        | sort -V | tail -n 1)"
    [[ -n "${platform}" ]] || return 1
    printf '%s\n' "${platform}"
}

installed_cmdline_tools_revision() {
    local props="${SDK_ROOT}/${CMDLINE_TOOLS_REL_DIR}/source.properties"
    [[ -f "${props}" ]] || return 1
    sed -n 's/^Pkg\.Revision=//p' "${props}" | head -n 1
}

installed_build_tools() {
    local dir="${SDK_ROOT}/build-tools"
    [[ -d "${dir}" ]] || return 1
    find "${dir}" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V
}

latest_installed_build_tools() {
    installed_build_tools | tail -n 1
}

# Text of `sdkmanager --list_installed`, or empty on failure.
list_installed_text() {
    "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --list_installed 2>/dev/null || true
}

# True when a package path appears in `sdkmanager --list_installed` output.
# Installed-list formats differ between sdkmanager releases:
#   build-tools;37.0.0 | 37.0.0 | ...   (classic sdkmanager)
#   build-tools/37.0.0   37.0.0   ...   (Android CLI based sdkmanager)
package_present_in_list() {
    local pkg="$1" text="$2" slash_pkg="${1//;/\/}"
    [[ -n "${text}" ]] || return 1
    awk -v semicolon="${pkg}" -v slash="${slash_pkg}" '
        {
            sub(/^[ \t]+/, "", $0)
            split($0, fields, /[ \t|]+/)
            if (fields[1] == semicolon || fields[1] == slash) found = 1
        }
        END { exit(found ? 0 : 1) }
    ' <<<"${text}"
}

# The Android CLI based sdkmanager can exit 0 while reporting that a package
# does not exist, so the log content has to be inspected as well.
sdkmanager_output_indicates_failure() {
    local logfile="${1:-${LAST_SDKMANAGER_LOG}}"
    [[ -n "${logfile}" && -f "${logfile}" ]] || return 1
    grep -qiE 'not found|failed to (install|download|uninstall)|package .*not installed' "${logfile}"
}

# Returns sdkmanager's exit status. Requires SDKMANAGER/SDK_ROOT to be set.
# Output goes to a temporary file: deleted on success, kept (with its path
# printed) on failure. No log directory is ever created.
sdkmanager_run() {
    local logfile rc
    logfile="$(mktemp "${TMPDIR:-/tmp}/android-sdk-sdkmanager.XXXXXX")" || {
        err "无法创建临时日志文件（mktemp）"
        return 1
    }
    set +e
    "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" "$@" 2>&1 | tee "${logfile}"
    rc=${PIPESTATUS[0]}
    set -e
    LAST_SDKMANAGER_LOG="${logfile}"
    if ((rc == 0)) && ! sdkmanager_output_indicates_failure "${logfile}"; then
        rm -f "${logfile}"
        LAST_SDKMANAGER_LOG=""
    else
        log "sdkmanager 输出保留在临时文件：${logfile}"
    fi
    return "${rc}"
}

# Accept every pending SDK license by feeding "y" to sdkmanager --licenses.
accept_licenses() {
    local logfile rc
    logfile="$(mktemp "${TMPDIR:-/tmp}/android-sdk-licenses.XXXXXX")" || {
        err "无法创建临时日志文件（mktemp）"
        return 1
    }
    log "接受 SDK 许可证（sdkmanager --licenses）"
    set +e
    "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --licenses < <(yes 2>/dev/null) >"${logfile}" 2>&1
    rc=$?
    set -e
    LAST_SDKMANAGER_LOG="${logfile}"
    if ((rc != 0)); then
        err "接受许可证失败（退出码 ${rc}）；输出：${logfile}"
        tail -n 20 "${logfile}" >&2 || true
        return 1
    fi
    rm -f "${logfile}"
    LAST_SDKMANAGER_LOG=""
    log "许可证已接受"
    return 0
}
