#!/usr/bin/env bash

# Install or upgrade ida-mcp from the official Hex-Rays Git repository.
#
# Exit codes:
#   0  installed, or already up to date
#   11 IDA Pro is not detected or unusable
#   12 the Python interpreter or pip is missing/unsupported
#   1  git is missing, an argument is invalid, or installation failed

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<'EOF'
Usage: install-idamcp.sh [--ref REF] [--python PATH] [--force] [--no-register]

Installs or upgrades ida-mcp into the selected Python environment:
  python -m pip install --upgrade git+https://github.com/HexRaysSA/ida-mcp.git

Options:
  --ref REF       Git ref (branch, tag, or commit) to install; default: main
  --python PATH   Python interpreter that receives ida-mcp; default: python3
  --force         Reinstall even when the installed version is already current
  --no-register   Do not add or update the IDA entry in .pi/mcp.json

IDA Pro detection:
  The script first runs check-idapro.sh, which looks for ~/.idapro. IDA Pro
  itself is never installed by this Skill.
EOF
}

ref=""
force=0
no_register=0

while (($# > 0)); do
    case "$1" in
        --ref)
            shift
            [[ $# -gt 0 ]] || { err "--ref requires a value"; exit 1; }
            ref="$1"
            ;;
        --ref=*)
            ref="${1#*=}"
            ;;
        --python)
            shift
            [[ $# -gt 0 ]] || { err "--python requires a value"; exit 1; }
            IDA_MCP_PYTHON="$1"
            ;;
        --python=*)
            IDA_MCP_PYTHON="${1#*=}"
            ;;
        --force|-f)
            force=1
            ;;
        --no-register)
            no_register=1
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

if [[ -n "${ref}" ]] && ! [[ "${ref}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    err "invalid --ref: ${ref}"
    exit 1
fi

log "步骤 1/5：检测 IDA Pro"
if ! "${script_dir}/check-idapro.sh"; then
    err "IDA Pro 检测未通过，已停止安装。"
    log "本 Skill 不安装 IDA Pro；请先安装并授权 IDA Pro 9.4+（含 idalib）。"
    exit 11
fi

log "步骤 2/5：检测 Python 环境"
if ! have "${IDA_MCP_PYTHON}"; then
    err "Python 解释器不可用：${IDA_MCP_PYTHON}"
    log "请先准备 Python ${IDA_MCP_MIN_PYTHON}+ 环境；本 Skill 不会自行安装运行时。"
    exit 12
fi

python_path="$(python_executable || true)"
if [[ -z "${python_path}" ]]; then
    err "无法解析 Python 解释器：${IDA_MCP_PYTHON}"
    exit 12
fi

if ! python_supported; then
    err "Python 版本过低：$(python_version || echo unknown)（${python_path}），需要 ${IDA_MCP_MIN_PYTHON}+"
    exit 12
fi
log "Python：${python_path}"

log "步骤 3/5：检查安装依赖"
if ! "${IDA_MCP_PYTHON}" -m pip --version >/dev/null 2>&1; then
    err "${python_path} 中没有可用的 pip"
    log "请先为该环境准备 pip；本 Skill 不会自行安装。"
    exit 12
fi

if ! have git; then
    err "未找到 git；从 GitHub 安装 ida-mcp 需要 git"
    exit 1
fi

log "步骤 4/5：安装/升级 ida-mcp"
current_version="$(idamcp_version || true)"
already_current=0
if [[ ${force} -eq 0 && -z "${ref}" ]]; then
    latest="$(upstream_version || true)"
    if [[ -z "${latest}" ]]; then
        warn "无法查询上游版本，继续执行安装"
    elif [[ -n "${current_version}" && "${current_version}" == "${latest}" ]]; then
        log "ida-mcp ${current_version} 已是最新"
        log "如需强制重装，使用 --force"
        already_current=1
    fi
fi

if ((already_current == 0)); then
    target="git+${IDA_MCP_REPO_URL}"
    if [[ -n "${ref}" ]]; then
        target="${target}@${ref}"
    fi

    pip_args=(install --upgrade)
    if [[ ${force} -eq 1 ]]; then
        pip_args+=(--force-reinstall)
    fi

    log "执行：${python_path} -m pip ${pip_args[*]} ${target}"
    if ! "${IDA_MCP_PYTHON}" -m pip "${pip_args[@]}" "${target}"; then
        err "ida-mcp 安装失败，请查看上方 pip 输出"
        exit 1
    fi

    new_version="$(idamcp_version || true)"
    if [[ -z "${new_version}" ]]; then
        err "安装命令已完成，但未检测到 ida-mcp；请检查 pip 输出"
        exit 1
    fi

    log "ida-mcp ${new_version} 已安装到 ${python_path}"
else
    new_version="${current_version}"
fi
command_path="$(idamcp_command || true)"
if [[ -n "${command_path}" ]]; then
    log "命令：${command_path}"
    log "启动 stdio MCP：${command_path} stdio --agent=pi"
else
    warn "未找到 ida-mcp 入口脚本，Python 环境可能不完整"
fi

register_mcp_config() {
    local mcp_tmp
    if ! have jq; then
        err "缺少 jq，无法安全修改 ${MCP_CONFIG}；本 Skill 不会自行安装"
        return 12
    fi

    mcp_tmp="$(mktemp "${MCP_CONFIG}.XXXXXX")"

    if [[ -s "${MCP_CONFIG}" ]]; then
        if ! jq -e '(.mcpServers // {}) | type == "object"' "${MCP_CONFIG}" >/dev/null 2>&1; then
            err "${MCP_CONFIG} 不是有效的 JSON，或其 mcpServers 不是对象"
            rm -f "${mcp_tmp}"
            return 1
        fi

        if ! jq \
            --arg name "${MCP_SERVER_NAME}" \
            --arg url "${MCP_URL}" \
            --arg description "${MCP_SERVER_DESCRIPTION}" \
            '.mcpServers = ((.mcpServers // {}) + {
                ($name): {
                    url: $url,
                    description: $description
                }
            })' "${MCP_CONFIG}" >"${mcp_tmp}"; then
            rm -f "${mcp_tmp}"
            return 1
        fi
    elif ! jq -n \
        --arg name "${MCP_SERVER_NAME}" \
        --arg url "${MCP_URL}" \
        --arg description "${MCP_SERVER_DESCRIPTION}" \
        '{
            mcpServers: {
                ($name): {
                    url: $url,
                    description: $description
                }
            }
        }' >"${mcp_tmp}"; then
        rm -f "${mcp_tmp}"
        return 1
    fi

    if ! jq empty "${mcp_tmp}"; then
        rm -f "${mcp_tmp}"
        return 1
    fi

    if ! mv "${mcp_tmp}" "${MCP_CONFIG}"; then
        rm -f "${mcp_tmp}"
        return 1
    fi
    chmod 644 "${MCP_CONFIG}"
}

log "步骤 5/5：注册 Pi MCP 配置"
if ((no_register)); then
    log "已跳过 .pi/mcp.json 注册（--no-register）"
else
    if ! register_mcp_config; then
        err "MCP 配置注册失败；ida-mcp ${new_version} 已安装，但 ${MCP_CONFIG} 未更新"
        exit 1
    fi
    log "已注册 ${MCP_SERVER_NAME} -> ${MCP_URL}"
    log "重启 Pi 或执行 /reload 使配置生效"
fi

log "启动 HTTP 服务：${script_dir}/start-idamcp-http.sh"
exit 0
