#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME}"
SERVICE_TAG="${SERVICE_TAG}"

############################################
# Resolve clients
############################################
CLIENTS=()

[ "${CLIENT1:-false}" = "true" ] && CLIENTS+=("flipkart")
[ "${CLIENT2:-false}" = "true" ] && CLIENTS+=("phonepe")

if [ "${#CLIENTS[@]}" -eq 0 ]; then
  echo "ERROR: No client selected"
  exit 1
fi

############################################
# Update parent repo
############################################
git checkout -b "update/${SERVICE_NAME}/${SERVICE_TAG}"

for CLIENT in "${CLIENTS[@]}"; do
  APP_FILE="applications/${CLIENT}/all-apps.yaml"

  if [ ! -f "$APP_FILE" ]; then
    echo "Skipping $CLIENT (no all-apps.yaml)"
    continue
  fi

  CHART_PATH=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"$SERVICE_NAME"'")
    | .spec.source.path
  ' "$APP_FILE")

  [ -z "$CHART_PATH" -o "$CHART_PATH" = "null" ] && continue

  VALUE_FILES=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"$SERVICE_NAME"'")
    | .spec.source.helm.valueFiles[]
  ' "$APP_FILE")

  for vf in $VALUE_FILES; do
    VALUES_PATH="${CHART_PATH}/${vf}"

    if [ ! -f "$VALUES_PATH" ]; then
      echo "WARNING: $VALUES_PATH not found"
      continue
    fi

    echo "Updating $SERVICE_NAME tag in $VALUES_PATH"
    yq -i '.image.tag = "'"$SERVICE_TAG"'"' "$VALUES_PATH"
  done
done

############################################
# Commit parent changes
############################################
git add -A
git commit -m "chore: update ${SERVICE_NAME} tag to ${SERVICE_TAG}"
git push origin HEAD

############################################
# Sync child repos (existing logic)
############################################
for CLIENT in "${CLIENTS[@]}"; do
  .github/scripts/sync-client.sh \
    "unused" \
    "${AUTO_MERGE}" \
    "${ORG}" \
    "${PARENT_REPO}" \
    "${TOKEN}"
done
