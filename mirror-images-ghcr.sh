#!/usr/bin/env bash

set -euo pipefail

# ----------------------------
# Variables - EDIT THESE
# ----------------------------
GH_USERNAME="ckgitrepouser"
GHCR_REPO="ckgitrepouser/prod/ck-nexus/postgres"
# PG_VERSION="15.2"
PG_VERSION="latest"   # optional

IMAGE_SRC="postgres:${PG_VERSION}"
IMAGE_DST="ghcr.io/${GHCR_REPO}:${PG_VERSION}"

echo "📌 Mirroring ${IMAGE_SRC} → ${IMAGE_DST}"

# ----------------------------
# 1. Login to GHCR
# ----------------------------
echo "🔐 Logging into GHCR..."
echo "${GH_PAT}" | docker login ghcr.io -u "${GH_USERNAME}" --password-stdin

# ----------------------------
# 2. Pull official PostgreSQL image
# ----------------------------
echo "⬇️ Pulling official PostgreSQL image..."
docker pull "${IMAGE_SRC}"

# ----------------------------
# 3. Tag for GHCR
# ----------------------------
echo "🏷️ Tagging image for GHCR..."
docker tag "${IMAGE_SRC}" "${IMAGE_DST}"

# ----------------------------
# 4. Push to GHCR
# ----------------------------
echo "⬆️ Pushing image to GHCR..."
docker push "${IMAGE_DST}"

# ----------------------------
# 5. Verify upload
# ----------------------------
echo "🧪 Verifying GHCR image..."
docker pull "${IMAGE_DST}"

echo "✅ Successfully mirrored ${IMAGE_SRC} → ${IMAGE_DST}"