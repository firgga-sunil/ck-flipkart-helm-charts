#!/usr/bin/env bash
set -euo pipefail

############################################
# Inputs
############################################
SERVICE_NAME="${SERVICE_NAME}"
SERVICE_TAG="${SERVICE_TAG}"
AUTO_MERGE="${AUTO_MERGE}"
ORG="${ORG}"
PARENT_REPO="${PARENT_REPO}"
TOKEN="${TOKEN}"
ORIGINAL_PWD="$(pwd)"

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

echo "Service: ${SERVICE_NAME}"
echo "Tag: ${SERVICE_TAG}"
echo "Clients: ${CLIENTS[*]}"

############################################
# Clone parent repo (once)
############################################
WORKDIR="$(mktemp -d)"
PARENT_DIR="${WORKDIR}/parent"

git clone "https://x-access-token:${TOKEN}@github.com/${PARENT_REPO}.git" "${PARENT_DIR}"
cd "${PARENT_DIR}"

git config user.name "template-sync-bot"
git config user.email "template-sync-bot@users.noreply.github.com"

PARENT_COMMIT="$(git rev-parse --short HEAD)"

############################################
# PHASE 1: Update parent values files
############################################
for CLIENT in "${CLIENTS[@]}"; do
  APP_FILE="${PARENT_DIR}/applications/${CLIENT}/all-apps.yaml"

  echo "============================================"
  echo "Updating ${SERVICE_NAME} tag to ${SERVICE_TAG} for client ${CLIENT}"
  echo "============================================"

  CHART_PATH=$(yq -r '
    .spec.applications[] |
    select(.name=="'"${SERVICE_NAME}"'") |
    .source.path
  ' "${APP_FILE}" 2>/dev/null || echo "")

  # If not found in applications array, try as standalone Application
  if [ -z "${CHART_PATH}" ] || [ "${CHART_PATH}" = "null" ]; then
    CHART_PATH=$(yq -r '
      select(.kind=="Application") |
      select(.metadata.name=="'"${SERVICE_NAME}"'") |
      .spec.source.path
    ' "${APP_FILE}" 2>/dev/null || echo "")
  fi

  if [ -z "${CHART_PATH}" ] || [ "${CHART_PATH}" = "null" ]; then
    echo "WARNING: No chart path found for ${SERVICE_NAME} in ${CLIENT}"
    continue
  fi

  echo "Chart path: ${CHART_PATH}"

  # Get value files - try both formats
  VALUE_FILES=$(yq -r '
    .spec.applications[] |
    select(.name=="'"${SERVICE_NAME}"'") |
    .source.helm.valueFiles[]?
  ' "${APP_FILE}" 2>/dev/null || echo "")

  if [ -z "${VALUE_FILES}" ]; then
    VALUE_FILES=$(yq -r '
      select(.kind=="Application") |
      select(.metadata.name=="'"${SERVICE_NAME}"'") |
      .spec.source.helm.valueFiles[]?
    ' "${APP_FILE}" 2>/dev/null || echo "")
  fi

  if [ -z "${VALUE_FILES}" ]; then
    echo "WARNING: No value files found for ${SERVICE_NAME}"
    continue
  fi

  echo "Value files to update:"
  for vf in ${VALUE_FILES}; do
    VALUES_PATH="${PARENT_DIR}/${CHART_PATH}/${vf}"
    echo "  - ${vf}"

    if [ -f "${VALUES_PATH}" ]; then
      # Show current tag
      CURRENT_TAG=$(yq -r '.image.tag // "not found"' "${VALUES_PATH}" 2>/dev/null || echo "error reading")
      echo "    Current tag: ${CURRENT_TAG}"
      
      # Update the tag
      yq -i '.image.tag = "'"${SERVICE_TAG}"'"' "${VALUES_PATH}"
      
      # Verify the update
      NEW_TAG=$(yq -r '.image.tag // "not found"' "${VALUES_PATH}" 2>/dev/null || echo "error reading")
      echo "    New tag: ${NEW_TAG}"
      
      if [ "${NEW_TAG}" = "${SERVICE_TAG}" ]; then
        echo "    ✓ Tag updated successfully"
      else
        echo "    ✗ WARNING: Tag update verification failed"
      fi
    else
      echo "    ✗ File not found: ${VALUES_PATH}"
    fi
  done
done

############################################
# Commit & push parent changes (DIRECT)
############################################
echo "============================================"
echo "Committing changes to parent repo"
echo "============================================"

if git status --porcelain | grep -q .; then
  git add -A
  git status --short
  git commit -m "chore: update ${SERVICE_NAME} tag to ${SERVICE_TAG}"
  git push origin main
  echo "✓ Pushed changes to parent repo"
else
  echo "ℹ No parent changes detected"
fi

############################################
# PHASE 2: Sync charts / apps / values to child repos
############################################
for CLIENT in "${CLIENTS[@]}"; do
  echo "============================================"
  echo "Syncing child repo for client: ${CLIENT}"
  echo "============================================"

  SYNC_PATHS=(
    "charts"
    "values/${CLIENT}"
    "applications/${CLIENT}"
  )

  TIMESTAMP="$(date +"%Y%m%d%H%M%S")-$$"
  BRANCH="sync/${CLIENT}/${TIMESTAMP}"
  CHILD_REPO="${ORG}/${CLIENT}-charts"
  CHILD_DIR="${WORKDIR}/child-${CLIENT}"

  ##########################################
  # Check if child repo exists, else create
  ##########################################
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${TOKEN}" \
    "https://api.github.com/repos/${CHILD_REPO}")

  if [ "${HTTP_CODE}" != "200" ]; then
    echo "Creating child repo ${CHILD_REPO}"

    curl -s -X POST \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/user/repos \
      -d "{
        \"name\": \"${CLIENT}-charts\",
        \"private\": true,
        \"auto_init\": false
      }" >/dev/null

    sleep 3
  fi

  ##########################################
  # Clone child repo
  ##########################################
  git clone "https://x-access-token:${TOKEN}@github.com/${CHILD_REPO}.git" "${CHILD_DIR}"
  cd "${CHILD_DIR}"

  git config user.name "template-sync-bot"
  git config user.email "template-sync-bot@users.noreply.github.com"

  ##########################################
  # Initialize main branch if needed
  ##########################################
  if ! git rev-parse --verify main >/dev/null 2>&1; then
    git checkout --orphan main
    git rm -rf . >/dev/null 2>&1 || true
    git commit --allow-empty -m "Initial commit"
    git push origin main
  fi

  ##########################################
  # Create sync branch
  ##########################################
  git checkout -b "${BRANCH}"

  ##########################################
  # Copy selected paths from parent → child
  ##########################################
  for p in "${SYNC_PATHS[@]}"; do
    src="${PARENT_DIR}/${p}"
    dest="${CHILD_DIR}/${p}"

    if [ -e "${src}" ]; then
      echo "Copying ${p}"
      mkdir -p "$(dirname "${dest}")"

      if [ -d "${src}" ]; then
        mkdir -p "${dest}"
        rsync -av --delete --exclude='.git' "${src}/" "${dest}/"
      elif [ -f "${src}" ]; then
        rsync -av "${src}" "${dest}"
      fi
    fi
  done

  ##########################################
  # Commit & push child changes
  ##########################################
  if git status --porcelain | grep -q .; then
    git add -A
    git commit -m "Sync from template ${PARENT_REPO}@${PARENT_COMMIT}

- Service: ${SERVICE_NAME}
- Tag: ${SERVICE_TAG}
- Client: ${CLIENT}"
    git push --set-upstream origin "${BRANCH}"

    ##########################################
    # Create PR
    ##########################################
    PR_JSON=$(jq -n \
      --arg title "Sync ${SERVICE_NAME}:${SERVICE_TAG} → ${CLIENT}" \
      --arg head "${BRANCH}" \
      --arg base "main" \
      --arg body "Automated sync from ${PARENT_REPO}@${PARENT_COMMIT}

**Service:** ${SERVICE_NAME}
**Tag:** ${SERVICE_TAG}
**Client:** ${CLIENT}" \
      '{title:$title, head:$head, base:$base, body:$body}')

    PR_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${CHILD_REPO}/pulls" \
      -d "${PR_JSON}")

    PR_NUMBER=$(echo "${PR_RESPONSE}" | jq -r '.number')

    if [ "${PR_NUMBER}" != "null" ] && [ -n "${PR_NUMBER}" ]; then
      echo "✓ PR #${PR_NUMBER} created: https://github.com/${CHILD_REPO}/pull/${PR_NUMBER}"

      ##########################################
      # Auto-merge (optional)
      ##########################################
      if [ "${AUTO_MERGE}" = "true" ]; then
        echo "Auto-merging PR #${PR_NUMBER}..."
        sleep 2
        
        MERGE_RESPONSE=$(curl -s -X PUT \
          -H "Authorization: token ${TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${CHILD_REPO}/pulls/${PR_NUMBER}/merge" \
          -d '{"merge_method":"squash"}')
        
        if echo "${MERGE_RESPONSE}" | jq -e '.merged' >/dev/null 2>&1; then
          echo "✓ PR #${PR_NUMBER} merged successfully"
        else
          echo "⚠ Failed to auto-merge: $(echo "${MERGE_RESPONSE}" | jq -r '.message')"
        fi
      fi
    else
      echo "✗ Failed to create PR: $(echo "${PR_RESPONSE}" | jq -r '.message // .errors[0].message')"
    fi
  else
    echo "ℹ No changes to sync for ${CLIENT}"
  fi

  cd "${PARENT_DIR}"
done

############################################
# Cleanup
############################################
echo "============================================"
rm -rf "${WORKDIR}"
cd "${ORIGINAL_PWD}"
echo "✓ Sync completed successfully"