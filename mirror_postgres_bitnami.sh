#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# Configuration - edit if needed
# ----------------------------
GH_USERNAME="ckgitrepouser"
GHCR_REPO="ckgitrepouser/prod/ck-nexus/postgres"
PG_VERSION="15.3.0"          # bitnami source version and tag for destination
# Source is the bitnami (legacy) PostgreSQL image you specified
IMAGE_SRC="bitnamilegacy/postgresql:${PG_VERSION}"
# Destination uses your requested ghcr repo style
IMAGE_DST="ghcr.io/${GHCR_REPO}:${PG_VERSION}"

# ----------------------------
# Preconditions
# ----------------------------
if [[ -z "${GHCR_PAT:-}" ]]; then
  echo "ERROR: GHCR_PAT is not set. Export it before running this script." >&2
  exit 1
fi

# Optional: check for docker availability
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker CLI not found in PATH." >&2
  exit 1
fi

# Optional: check for buildx support
if ! docker buildx version >/dev/null 2>&1; then
  echo "WARNING: docker buildx not available or not configured. imagetools step may fail and fallback will be used."
fi

# ----------------------------
# 1) Login to GHCR
# ----------------------------
echo "Logging into ghcr.io as ${GH_USERNAME}..."
echo "${GHCR_PAT}" | docker login ghcr.io -u "${GH_USERNAME}" --password-stdin

# ----------------------------
# 2) Attempt multi-arch mirror using imagetools (buildx imagetools)
# ----------------------------
echo "Attempting multi-arch manifest copy: ${IMAGE_SRC} -> ${IMAGE_DST}"
set +e
docker buildx imagetools create --tag "${IMAGE_DST}" "${IMAGE_SRC}" 2>/dev/null
IMAGETOOLS_EXIT=$?
set -e

if [[ "${IMAGETOOLS_EXIT}" -eq 0 ]]; then
  echo "Multi-arch manifest successfully copied to ${IMAGE_DST}."
else
  echo "imagetools failed (exit ${IMAGETOOLS_EXIT}); falling back to pull/tag/push (single-arch)."
  # ----------------------------
  # 3) Fallback: pull, tag, push
  # ----------------------------
  echo "Pulling source image ${IMAGE_SRC}..."
  docker pull "${IMAGE_SRC}"
  echo "Tagging ${IMAGE_SRC} -> ${IMAGE_DST}..."
  docker tag "${IMAGE_SRC}" "${IMAGE_DST}"
  echo "Pushing ${IMAGE_DST}..."
  docker push "${IMAGE_DST}"
  echo "Fallback push complete."
fi

# ----------------------------
# 4) Verify upload by pulling the destination image
# ----------------------------
echo "Verifying that ${IMAGE_DST} is available by attempting to pull it..."
# Attempt pull up to 3 times with a small backoff in case GHCR needs a moment
MAX_ATTEMPTS=3
attempt=1
while :; do
  if docker pull "${IMAGE_DST}"; then
    echo "Verification succeeded: pulled ${IMAGE_DST}."
    break
  else
    if [[ ${attempt} -ge ${MAX_ATTEMPTS} ]]; then
      echo "ERROR: Verification failed after ${MAX_ATTEMPTS} attempts. ${IMAGE_DST} may not be available." >&2
      exit 1
    fi
    echo "Pull failed; retrying (attempt ${attempt}/${MAX_ATTEMPTS})..."
    attempt=$((attempt + 1))
    sleep 2
  fi
done

echo "Done. ${IMAGE_SRC} -> ${IMAGE_DST} mirrored and verified."
