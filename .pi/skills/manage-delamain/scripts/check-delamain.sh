#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
# shellcheck source=config.sh
source "${script_dir}/config.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [--quiet]

Check the delamain container, health endpoint and MCP tools/list.

Exit codes:
  0   container running, healthy and MCP callable
  1   container/health/MCP problem
  10  Docker daemon is not accessible
EOF
}

QUIET=0
while (($# > 0)); do
    case "$1" in
        --quiet)
            QUIET=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1 (use --help)"
            ;;
    esac
done

require_commands || exit $?
docker_ok || exit $?

if ! require_installed; then
    exit 1
fi

mkdir -p "${LOG_DIR}"
CHECK_LOG="${LOG_DIR}/check.log"
: >"${CHECK_LOG}"

failures=0

state="$(container_state)"
health_state="$(container_health)"
printf 'container=%s health=%s\n' "${state}" "${health_state}" | tee -a "${CHECK_LOG}"
if [[ "${state}" != "running" ]]; then
    printf 'DELAMAIN_CONTAINER_NOT_RUNNING: %s\n' "${state}" | tee -a "${CHECK_LOG}" >&2
    failures=$((failures + 1))
fi

health_json="$(health_payload)"
printf 'health_payload=%s\n' "${health_json:-<empty>}" >>"${CHECK_LOG}"
if [[ -n "${health_json}" ]] && printf '%s' "${health_json}" | jq -e '.status == "healthy"' >/dev/null 2>&1; then
    if ((QUIET == 0)); then
        printf 'health=healthy version=%s jadx=%s\n' \
            "$(printf '%s' "${health_json}" | jq -r '.version // "?"')" \
            "$(printf '%s' "${health_json}" | jq -r '.jadx_version // "?"')"
    fi
else
    printf 'DELAMAIN_UNHEALTHY: /health is not healthy\n' >&2
    failures=$((failures + 1))
fi

token="${TOKEN:-}"
if [[ -z "${token}" ]]; then
    token="$(read_token_from_auth_file)"
fi
if [[ -z "${token}" ]]; then
    printf 'DELAMAIN_TOKEN_MISSING: %s is empty\n' "${AUTH_FILE}" >&2
    failures=$((failures + 1))
elif ((failures == 0)); then
    if mcp_probe "${token}" >>"${CHECK_LOG}" 2>&1; then
        tool_count="$(grep -oE 'Authenticated tools/list: [0-9]+' "${CHECK_LOG}" | tail -n 1 | awk '{print $3}')"
        if ((QUIET == 0)); then
            printf 'mcp=tools/%s\n' "${tool_count:-?}"
        fi
    else
        printf 'DELAMAIN_MCP_PROBE_FAILED: see %s\n' "${CHECK_LOG}" >&2
        failures=$((failures + 1))
    fi
fi

if ((failures == 0)); then
    if ((QUIET == 0)); then
        printf 'delamain is ready: %s\n' "${MCP_URL}"
    fi
    exit 0
fi

printf 'delamain is not ready (%d problem(s)); details: %s\n' "${failures}" "${CHECK_LOG}" >&2
exit 1
