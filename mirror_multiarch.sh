#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
GHCR_OWNER="ckgitrepouser"           # change if needed
GHCR_REG="ghcr.io/${GHCR_OWNER}"

# list of pairs: "SOURCE_IMAGE TARGET_REPO:TAG"
# You can add/remove lines here in your preferred "SRC DST" style
IMAGES=(
  "quay.io/argoproj/argocd:v3.2.1 ${GHCR_REG}/argocd:v3.2.1"
  "ghcr.io/dexidp/dex:v2.39.1 ${GHCR_REG}/dex:v2.39.1"
  "redis:8.4.0-alpine ${GHCR_REG}/redis:8.4.0-alpine"
  "ghcr.io/oliver006/redis_exporter:v1.80.1 ${GHCR_REG}/redis_exporter:v1.80.1"
)

# === END CONFIG ===

log() { printf '[%s] %s\n' "$(date +'%Y-%m-%dT%H:%M:%S')" "$*"; }

if [[ -z "${GHCR_PAT:-}" ]]; then
  echo "ERROR: GHCR_PAT must be exported. Example: export GHCR_PAT=xxxxx" >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "docker required"; exit 1; }
command -v jq >/dev/null 2>&1 || log "Note: jq not found; output will be raw."

log "Logging into GHCR as ${GHCR_OWNER}"
echo "${GHCR_PAT}" | docker login ghcr.io -u "${GHCR_OWNER}" --password-stdin

# Ensure buildx available
if ! docker buildx version &>/dev/null; then
  echo "ERROR: docker buildx not available. Install Docker Buildx." >&2
  exit 1
fi

BUILDER_NAME="multiarch-mirror-builder"
if ! docker buildx ls | grep -q "${BUILDER_NAME}"; then
  log "Creating buildx builder ${BUILDER_NAME}"
  docker buildx create --name "${BUILDER_NAME}" --driver docker-container --use >/dev/null
  docker buildx inspect --bootstrap >/dev/null
else
  log "Using existing buildx builder ${BUILDER_NAME}"
  docker buildx use "${BUILDER_NAME}"
fi

SUCCESS=0
FAILED=0

for pair in "${IMAGES[@]}"; do
  # split pair (safe even if tags have colons)
  set -- $pair
  SRC="$1"
  DST="$2"

  log "Processing: ${SRC} -> ${DST}"

  # Try to use imagetools.create (this preserves manifest lists / multi-arch)
  if docker buildx imagetools create --tag "${DST}" "${SRC}" 2>/dev/null; then
    log "✅ imagetools created ${DST} (multi-arch if upstream provided)"
    ((SUCCESS++))
  else
    log "⚠️ imagetools failed; falling back to pull/tag/push for ${SRC}"

    # Fallback: pull/tag/push (single-arch image push; will not create multiarch manifest lists)
    if docker pull "${SRC}"; then
      docker tag "${SRC}" "${DST}"
      docker push "${DST}"
      log "✅ Fallback pushed ${DST}"
      ((SUCCESS++))
    else
      log "❌ Failed to pull ${SRC}"
      ((FAILED++))
    fi
  fi
done

log "Finished. Success: ${SUCCESS}, Failed: ${FAILED}"
log "Mirrored images are under: ${GHCR_REG}"
