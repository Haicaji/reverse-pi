#!/usr/bin/env bash

# Detect IDA Pro through its user configuration directory (~/.idapro).
#
# IDA Pro creates ~/.idapro on first start; this is the only marker used.
#
# Exit codes:
#   0  IDA Pro detected
#   10 IDA Pro not detected

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd -P)"
# shellcheck source=./config.sh
source "${script_dir}/config.sh"

usage() {
    cat <<EOF
Usage: check-idapro.sh

Detects IDA Pro by looking for the user configuration directory:
  ${IDAPRO_USER_DIR}

Override the location with IDAPRO_USER_DIR when IDA uses a non-standard home.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    "")
        ;;
    *)
        err "unknown argument: $1"
        usage >&2
        exit 1
        ;;
esac

if [[ ! -d "${IDAPRO_USER_DIR}" ]]; then
    err "未检测到 IDA Pro：${IDAPRO_USER_DIR} 不存在"
    log "IDA Pro 首次启动后会创建该目录；请先安装 IDA Pro 9.4+（含 idalib）并启动一次、接受许可证。"
    exit 10
fi

log "已检测到 IDA Pro 用户配置目录：${IDAPRO_USER_DIR}"

exit 0
