#!/usr/bin/env bash
set -euo pipefail

### >>>>> CONFIGURABLE SECTION <<<<<

# Your GHCR owner (GitHub org or username)
GHCR_OWNER="ckgitrepouser"
GHCR_REG="ghcr.io/${GHCR_OWNER}"

# Versions (update these when you bump Argo CD chart/app)
ARGOCD_TAG="v3.2.1"
DEX_TAG="v2.39.1"
REDIS_TAG="8.4.0-alpine"
EXPORTER_TAG="v1.80.1"

# Upstream image locations
ARGOCD_UPSTREAM="quay.io/argoproj/argocd:${ARGOCD_TAG}"
DEX_UPSTREAM="ghcr.io/dexidp/dex:${DEX_TAG}"
REDIS_UPSTREAM="redis:${REDIS_TAG}"   # docker.io/library/redis
EXPORTER_UPSTREAM="ghcr.io/oliver006/redis_exporter:${EXPORTER_TAG}"

# Target image names in your GHCR
ARGOCD_MIRROR="${GHCR_REG}/argocd:${ARGOCD_TAG}"
DEX_MIRROR="${GHCR_REG}/dex:${DEX_TAG}"
REDIS_MIRROR="${GHCR_REG}/redis:${REDIS_TAG}"
EXPORTER_MIRROR="${GHCR_REG}/redis_exporter:${EXPORTER_TAG}"

### >>>>> END CONFIGURABLE SECTION <<<<<

log() {
  printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S')" "$*" >&2
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: '$1' not found in PATH" >&2
    exit 1
  fi
}

main() {
  require docker

  if [[ -z "${GHCR_PAT:-}" ]]; then
    echo "ERROR: GHCR_PAT environment variable must be set (GitHub PAT with read/write:packages)" >&2
    exit 1
  fi

  log "Logging in to GHCR as ${GHCR_OWNER}"
  echo "${GHCR_PAT}" | docker login ghcr.io -u "${GHCR_OWNER}" --password-stdin

  # Array of "UPSTREAM TARGET" pairs
  IMAGES=(
    "${ARGOCD_UPSTREAM} ${ARGOCD_MIRROR}"
    "${DEX_UPSTREAM} ${DEX_MIRROR}"
    "${REDIS_UPSTREAM} ${REDIS_MIRROR}"
    "${EXPORTER_UPSTREAM} ${EXPORTER_MIRROR}"
  )

  for pair in "${IMAGES[@]}"; do
    # shellcheck disable=SC2086
    set -- $pair
    SRC="$1"
    DST="$2"

    log "Mirroring ${SRC} -> ${DST}"
    docker pull "${SRC}"
    docker tag  "${SRC}" "${DST}"
    docker push "${DST}"
  done

  log "Done. Mirrored images:"
  printf '  %s\n' "${ARGOCD_MIRROR}" "${DEX_MIRROR}" "${REDIS_MIRROR}" "${EXPORTER_MIRROR}"
}

main "$@"
