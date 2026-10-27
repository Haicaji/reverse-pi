#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
# shellcheck source=config.sh
source "${script_dir}/config.sh"

usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [--quiet]

Check whether a newer delamain image is available for ${IMAGE}.

Exit codes:
  0   image is up to date and used by the running container
  20  update available (new image, missing image, or stale container)
  1   update check failed
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

platform="$(platform_string)"
if ((QUIET == 0)); then
    log "checking ${IMAGE} (${platform})"
fi

if ! remote_digest="$(remote_image_digest "${IMAGE}")"; then
    echo "DELAMAIN_UPDATE_CHECK_FAILED: cannot read the remote manifest for ${IMAGE}." >&2
    echo "Check access to the image registry, then retry." >&2
    exit 1
fi
if [[ -z "${remote_digest}" ]]; then
    echo "DELAMAIN_UPDATE_CHECK_FAILED: no manifest found for platform ${platform} in ${IMAGE}." >&2
    exit 1
fi

local_digest="$(local_image_digest "${IMAGE}")"
status="up-to-date"
if [[ -z "${local_digest}" ]]; then
    status="not-installed"
elif [[ "${local_digest}" != "${remote_digest}" ]]; then
    status="update-available"
else
    image_id="$(local_image_id "${IMAGE}")"
    running_id="$(container_image_id)"
    if [[ -n "${image_id}" && -n "${running_id}" && "${running_id}" != "${image_id}" ]]; then
        status="restart-required"
    fi
fi

if ((QUIET == 0)); then
    printf 'image=%s\n' "${IMAGE}"
    printf 'platform=%s\n' "${platform}"
    printf 'local_digest=%s\n' "${local_digest:-<missing>}"
    printf 'remote_digest=%s\n' "${remote_digest}"
    printf 'status=%s\n' "${status}"
fi

case "${status}" in
    up-to-date)
        if ((QUIET == 0)); then
            printf 'delamain image is up to date.\n'
        fi
        exit 0
        ;;
    restart-required)
        echo "DELAMAIN_UPDATE_AVAILABLE: the new image is already pulled; rerun scripts/install-delamain.sh to recreate the container." >&2
        exit 20
        ;;
    update-available)
        echo "DELAMAIN_UPDATE_AVAILABLE: a newer image is available; rerun scripts/install-delamain.sh to upgrade." >&2
        exit 20
        ;;
    not-installed)
        echo "DELAMAIN_IMAGE_MISSING: the image is not present locally; run scripts/install-delamain.sh." >&2
        exit 20
        ;;
esac
