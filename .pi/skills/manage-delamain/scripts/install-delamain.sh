#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
# shellcheck source=config.sh
source "${script_dir}/config.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [OPTIONS] [APK_DIR]

Install or update the delamain container and wire it into .pi/mcp.json.

Arguments:
  APK_DIR                 Host directory mounted at /apks (default: ${DEFAULT_APK_DIR})

Options:
  --apk-dir DIR           Same as APK_DIR
  --rotate-token          Generate a new MCP bearer token and update the auth file
  --no-pull               Skip pulling the latest image
  --force                 Recreate the container even if it is already running
  -h, --help              Show this help
EOF
}

APK_DIR_ARG=""
ROTATE_TOKEN=0
NO_PULL=0
FORCE=0

while (($# > 0)); do
    case "$1" in
        --apk-dir)
            [[ $# -ge 2 ]] || die "--apk-dir requires a directory"
            APK_DIR_ARG="$2"
            shift 2
            ;;
        --rotate-token)
            ROTATE_TOKEN=1
            shift
            ;;
        --no-pull)
            NO_PULL=1
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            die "unknown option: $1 (use --help)"
            ;;
        *)
            APK_DIR_ARG="$1"
            shift
            ;;
    esac
done

if [[ -n "${APK_DIR_ARG}" ]]; then
    APK_DIR="${APK_DIR_ARG}"
fi

if [[ -n "${IMAGE_MIGRATED_FROM}" ]]; then
    log "migrating pinned image '${IMAGE_MIGRATED_FROM}' to ${IMAGE}"
fi

require_commands || exit $?
docker_ok || exit $?

if port_in_use; then
    if our_container_running; then
        log "port ${PORT} is already served by ${CONTAINER_NAME}"
    else
        echo "DELAMAIN_PORT_IN_USE: port ${PORT} is already in use by another process." >&2
        ss -ltnp 2>/dev/null | grep -E "[:.]${PORT}[[:space:]]" >&2 || true
        cat >&2 <<EOF
Identify the process or service that owns the port, stop it, then rerun this
installer. This Skill never kills user-owned processes.

    ss -ltnp | grep ':${PORT}'

If it is a stopped old container, remove it explicitly; if it is another MCP
server, stop that service first.
EOF
        exit 1
    fi
fi

if [[ -z "${APK_DIR}" ]]; then
    die "APK directory is empty"
fi
mkdir -p "${APK_DIR}"
APK_DIR="$(readlink -f "${APK_DIR}")"

mkdir -p "${STATE_DIR}" "${STATE_DIR}/output" "${STATE_DIR}/indices" \
    "${STATE_DIR}/config" "${STATE_DIR}/backups" "${STATE_DIR}/logs"
chmod 700 "${STATE_DIR}"

if ((ROTATE_TOKEN)) || [[ -z "${TOKEN}" ]]; then
    TOKEN="$(generate_token)"
fi

write_env_file
write_auth_file

install -m 0644 "${script_dir}/delamain-compose.yml" "${COMPOSE_FILE}"

# Add or update the Delamain entry in .pi/mcp.json without touching other
# servers. A timestamped backup is kept so an interrupted run never loses the
# previous configuration.
MCP_CONFIG="${REPO_ROOT}/.pi/mcp.json"
timestamp="$(date +%Y%m%d-%H%M%S)"
if [[ -f "${MCP_CONFIG}" ]]; then
    cp -p "${MCP_CONFIG}" "${BACKUP_DIR}/mcp.json.${timestamp}"
fi

# Resolve the token without embedding an absolute checkout path: walk up from
# the current directory until the repository's .pi/secrets file is found, so
# the same config works from the repo root and from Pi's workdir/ cwd.
if [[ "${AUTH_FILE}" == "${REPO_ROOT}/.pi/secrets/delamain.auth" ]]; then
    auth_command='!d=$PWD; while [ ! -f "$d/.pi/secrets/delamain.auth" ] && [ "$d" != "/" ]; do d=$(dirname "$d"); done; cat "$d/.pi/secrets/delamain.auth"'
else
    auth_command="!cat '${AUTH_FILE}'"
fi

mcp_tmp="$(mktemp "${REPO_ROOT}/.pi/.mcp.json.XXXXXX")"
trap 'rm -f "${mcp_tmp}"' EXIT
if [[ -s "${MCP_CONFIG}" ]]; then
    if ! jq -e '(.mcpServers // {}) | type == "object"' "${MCP_CONFIG}" >/dev/null 2>&1; then
        echo "DELAMAIN_MCP_CONFIG_INVALID: ${MCP_CONFIG} is not valid JSON or its mcpServers is not an object." >&2
        echo "The original file was left untouched; fix or move it, then rerun this installer." >&2
        exit 1
    fi
    jq \
        --arg url "${MCP_URL}" \
        --arg auth "${auth_command}" \
        --arg description "Headless JADX Android reverse-engineering MCP (delamain): load APK/DEX, decompile, search, xrefs, resources, Frida hooks." \
        '.mcpServers = ((.mcpServers // {}) + {
            Delamain: {
                url: $url,
                headers: { Authorization: $auth },
                description: $description
            }
        })' "${MCP_CONFIG}" >"${mcp_tmp}"
else
    jq -n \
        --arg url "${MCP_URL}" \
        --arg auth "${auth_command}" \
        --arg description "Headless JADX Android reverse-engineering MCP (delamain): load APK/DEX, decompile, search, xrefs, resources, Frida hooks." \
        '{
            mcpServers: {
                Delamain: {
                    url: $url,
                    headers: { Authorization: $auth },
                    description: $description
                }
            }
        }' >"${mcp_tmp}"
fi
jq empty "${mcp_tmp}"
mv "${mcp_tmp}" "${MCP_CONFIG}"
chmod 644 "${MCP_CONFIG}"

if ((NO_PULL == 0)); then
    log "pulling ${IMAGE}"
    compose pull
fi

log "starting ${CONTAINER_NAME} on 127.0.0.1:${PORT}"
if ((FORCE)); then
    compose up -d --force-recreate
else
    compose up -d
fi

log "waiting for /health (up to 180s)"
if ! health_json="$(wait_for_health 180)"; then
    echo "DELAMAIN_HEALTH_TIMEOUT: /health did not become healthy." >&2
    compose ps >&2 || true
    compose logs --tail=100 >&2 || true
    exit 1
fi

if ! mcp_probe "${TOKEN}"; then
    echo "DELAMAIN_MCP_PROBE_FAILED: the MCP endpoint is not callable." >&2
    compose logs --tail=100 >&2 || true
    exit 1
fi

cat <<EOF

delamain is ready.

  MCP endpoint : ${MCP_URL}
  APK directory: ${APK_DIR}  (mounted at /apks)
  State        : ${STATE_DIR}
  Auth file    : ${AUTH_FILE}
  Container    : ${CONTAINER_NAME}
  Image        : ${IMAGE}
  Image ID     : $(local_image_id "${IMAGE}")
  Health       : $(printf '%s' "${health_json}" | jq -c . 2>/dev/null || printf '%s' "${health_json}")

Next steps:
  1. Restart Pi, or run /reload, so it reads the updated .pi/mcp.json.
  2. Verify the connection with: pi mcp list
  3. Put APK/DEX files in ${APK_DIR}, then call load_file_tool(path="...")
     through the Delamain MCP server.
  4. Check for future image updates with: ${script_dir}/check-update-delamain.sh
EOF
