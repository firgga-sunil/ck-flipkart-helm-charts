#!/usr/bin/env bash
set -euo pipefail

GHCR_OWNER="ckgitrepouser"
GHCR_REG="ghcr.io/${GHCR_OWNER}"

# List the GHCR images you expect to exist (full name: ghcr.io/owner/path:tag)
EXPECT=(
  "${GHCR_REG}/argocd:v3.2.1"
  "${GHCR_REG}/dex:v2.39.1"
  "${GHCR_REG}/redis:8.4.0-alpine"
  "${GHCR_REG}/redis_exporter:v1.80.1"
  "${GHCR_REG}/prod/bitnami-postgresql:15.3.0"  # adjust if you used different DST
)

if [[ -z "${GHCR_PAT:-}" ]]; then
  echo "ERROR: set GHCR_PAT to authenticate to GHCR for any private images (export GHCR_PAT=...)" >&2
  exit 1
fi

echo "Logging in..."
echo "${GHCR_PAT}" | docker login ghcr.io -u "${GHCR_OWNER}" --password-stdin >/dev/null

MISSING=0

for img in "${EXPECT[@]}"; do
  echo "----------------------------------------"
  echo "Checking: ${img}"
  if docker buildx imagetools inspect "${img}" >/dev/null 2>&1; then
    echo "✅ Exists: ${img}"
    # show platforms (grep for 'platform:')
    PLAT_OUT=$(docker buildx imagetools inspect "${img}" --raw 2>/dev/null || true)
    if echo "${PLAT_OUT}" | grep -qi "platform"; then
      echo "Detected platforms:"
      echo "${PLAT_OUT}" | sed -n '1,200p' | grep -E "platform|architecture|os" | sed 's/^/  /'
    else
      echo "  (No platform list shown — likely single-arch or unknown manifest format)"
      # try pulling to verify
      echo "Attempting docker pull to verify availability..."
      if docker pull "${img}"; then
        echo "  docker pull OK (image available)"
      else
        echo "  docker pull failed"
      fi
    fi
  else
    echo "❌ Missing: ${img}"
    MISSING=1
  fi
done

echo "----------------------------------------"
if [ "${MISSING}" -eq 0 ]; then
  echo "✅ Validation: all expected images exist (but double-check platforms for each above)"
  exit 0
else
  echo "⚠️ Validation: some images are missing. See output above."
  exit 1
fi
