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
  APP_DIR="${PARENT_DIR}/applications/${CLIENT}"
  APP_FILE="${APP_DIR}/all-apps.yaml"

  # Check if applications directory exists
  if [ ! -d "${APP_DIR}" ]; then
    echo "WARNING: Applications directory ${APP_DIR} does not exist, skipping values update for ${CLIENT}"
    continue
  fi

  # Check if all-apps.yaml exists
  if [ ! -f "${APP_FILE}" ]; then
    echo "WARNING: ${APP_FILE} not found, skipping values update for ${CLIENT}"
    echo "Available files in ${APP_DIR}:"
    ls -la "${APP_DIR}" || echo "  (unable to list directory)"
    continue
  fi

  echo "Updating ${SERVICE_NAME} values for client ${CLIENT}"
  echo "Reading from: ${APP_FILE}"

  CHART_PATH=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"${SERVICE_NAME}"'")
    | .spec.source.path
  ' "${APP_FILE}" || echo "")

  if [ -z "${CHART_PATH}" ] || [ "${CHART_PATH}" = "null" ]; then
    echo "No ArgoCD Application found for ${SERVICE_NAME} in ${CLIENT}"
    continue
  fi

  echo "Found chart path: ${CHART_PATH}"

  VALUE_FILES=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"${SERVICE_NAME}"'")
    | .spec.source.helm.valueFiles[]?
  ' "${APP_FILE}" || echo "")

  if [ -z "${VALUE_FILES}" ]; then
    echo "No value files found for ${SERVICE_NAME} in ${CLIENT}"
    continue
  fi

  for vf in ${VALUE_FILES}; do
    VALUES_PATH="${PARENT_DIR}/${CHART_PATH}/${vf}"

    if [ ! -f "${VALUES_PATH}" ]; then
      echo "WARNING: ${VALUES_PATH} not found"
      continue
    fi

    echo "Updating tag in ${VALUES_PATH}"
    yq -i '.image.tag = "'"${SERVICE_TAG}"'"' "${VALUES_PATH}"
  done
done

############################################
# Commit & push parent changes (DIRECT)
############################################
if git status --porcelain | grep -q .; then
  git add -A
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

  # Define paths to sync - only include paths that exist
  SYNC_PATHS=()
  
  # Always try to sync charts
  if [ -d "${PARENT_DIR}/charts" ]; then
    SYNC_PATHS+=("charts")
  else
    echo "WARNING: charts directory not found"
  fi
  
  # Sync client-specific values
  if [ -d "${PARENT_DIR}/values/${CLIENT}" ]; then
    SYNC_PATHS+=("values/${CLIENT}")
  else
    echo "WARNING: values/${CLIENT} directory not found"
  fi
  
  # Sync client-specific applications
  if [ -d "${PARENT_DIR}/applications/${CLIENT}" ]; then
    SYNC_PATHS+=("applications/${CLIENT}")
  else
    echo "WARNING: applications/${CLIENT} directory not found"
  fi

  if [ "${#SYNC_PATHS[@]}" -eq 0 ]; then
    echo "ERROR: No valid paths to sync for ${CLIENT}, skipping"
    continue
  fi

  echo "Paths to sync: ${SYNC_PATHS[*]}"

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

    CREATE_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      https://api.github.com/user/repos \
      -d "{
        \"name\": \"${CLIENT}-charts\",
        \"private\": true,
        \"auto_init\": false
      }")

    if echo "${CREATE_RESPONSE}" | jq -e '.id' >/dev/null 2>&1; then
      echo "✓ Repository created successfully"
    else
      echo "WARNING: Repository creation response: ${CREATE_RESPONSE}"
    fi

    sleep 3
  fi

  ##########################################
  # Clone child repo
  ##########################################
  echo "Cloning child repo..."
  git clone "https://x-access-token:${TOKEN}@github.com/${CHILD_REPO}.git" "${CHILD_DIR}"
  cd "${CHILD_DIR}"

  git config user.name "template-sync-bot"
  git config user.email "template-sync-bot@users.noreply.github.com"

  ##########################################
  # Initialize main branch if needed
  ##########################################
  if ! git rev-parse --verify main >/dev/null 2>&1; then
    echo "Initializing main branch..."
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

    if [ ! -e "${src}" ]; then
      echo "WARNING: Source path ${src} does not exist, skipping"
      continue
    fi

    echo "Copying ${src} -> ${dest}"
    mkdir -p "$(dirname "${dest}")"

    if [ -d "${src}" ]; then
      # Copy directory contents
      mkdir -p "${dest}"
      rsync -av --delete --exclude='.git' "${src}/" "${dest}/"
    elif [ -f "${src}" ]; then
      # Copy single file
      rsync -av "${src}" "${dest}"
    fi
  done

  ##########################################
  # Commit & push child changes
  ##########################################
  if git status --porcelain | grep -q .; then
    git add -A
    git commit -m "Sync from template ${PARENT_REPO}@${PARENT_COMMIT} for ${CLIENT}

- Updated ${SERVICE_NAME} to ${SERVICE_TAG}
- Synced: ${SYNC_PATHS[*]}"
    git push --set-upstream origin "${BRANCH}"

    ##########################################
    # Create PR
    ##########################################
    PR_JSON=$(jq -n \
      --arg title "Sync from template ${PARENT_COMMIT} → ${CLIENT}" \
      --arg head "${BRANCH}" \
      --arg base "main" \
      --arg body "Automated sync from ${PARENT_REPO} commit ${PARENT_COMMIT}

**Changes:**
- Service: ${SERVICE_NAME}
- Tag: ${SERVICE_TAG}
- Synced paths: ${SYNC_PATHS[*]}" \
      '{title:$title, head:$head, base:$base, body:$body}')

    PR_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${CHILD_REPO}/pulls" \
      -d "${PR_JSON}")

    PR_NUMBER=$(echo "${PR_RESPONSE}" | jq -r '.number')

    if [ "${PR_NUMBER}" != "null" ] && [ -n "${PR_NUMBER}" ]; then
      echo "✓ PR #${PR_NUMBER} created for ${CLIENT}"
      echo "  URL: https://github.com/${CHILD_REPO}/pull/${PR_NUMBER}"

      ##########################################
      # Auto-merge (optional)
      ##########################################
      if [ "${AUTO_MERGE}" = "true" ]; then
        echo "Auto-merging PR #${PR_NUMBER}..."
        sleep 2  # Brief delay to let PR be fully created
        
        MERGE_RESPONSE=$(curl -s -X PUT \
          -H "Authorization: token ${TOKEN}" \
          -H "Accept: application/vnd.github+json" \
          "https://api.github.com/repos/${CHILD_REPO}/pulls/${PR_NUMBER}/merge" \
          -d '{"merge_method":"squash"}')
        
        MERGE_STATUS=$(echo "${MERGE_RESPONSE}" | jq -r '.merged // false')
        if [ "${MERGE_STATUS}" = "true" ]; then
          echo "✓ PR #${PR_NUMBER} merged successfully"
        else
          echo "⚠ Failed to auto-merge PR #${PR_NUMBER}"
          echo "${MERGE_RESPONSE}" | jq -r '.message // "Unknown error"'
        fi
      fi
    else
      echo "✗ Failed to create PR for ${CLIENT}"
      echo "${PR_RESPONSE}" | jq -r '.message // .errors // "Unknown error"'
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
echo "Cleanup: Removing temporary directory"
rm -rf "${WORKDIR}"
cd "${ORIGINAL_PWD}"
echo "✓ Sync completed successfully"