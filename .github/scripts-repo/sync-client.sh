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
  APP_FILE="applications/${CLIENT}/all-apps.yaml"

  if [ ! -f "${APP_FILE}" ]; then
    echo "Skipping ${CLIENT} (no all-apps.yaml)"
    continue
  fi

  echo "Updating ${SERVICE_NAME} values for client ${CLIENT}"

  CHART_PATH=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"${SERVICE_NAME}"'")
    | .spec.source.path
  ' "${APP_FILE}")

  if [ -z "${CHART_PATH}" ] || [ "${CHART_PATH}" = "null" ]; then
    echo "No ArgoCD Application found for ${SERVICE_NAME} in ${CLIENT}"
    continue
  fi

  VALUE_FILES=$(yq -r '
    select(.kind=="Application")
    | select(.metadata.name=="'"${SERVICE_NAME}"'")
    | .spec.source.helm.valueFiles[]?
  ' "${APP_FILE}")

  for vf in ${VALUE_FILES}; do
    VALUES_PATH="${CHART_PATH}/${vf}"

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
else
  echo "No parent changes detected"
fi

############################################
# PHASE 2: Sync charts / apps / values to child repos
############################################
for CLIENT in "${CLIENTS[@]}"; do
  echo "--------------------------------------------"
  echo "Syncing child repo for client: ${CLIENT}"
  echo "--------------------------------------------"

  SYNC_PATHS=(
    "charts"
    "applications/${CLIENT}/all-apps.yaml"
    "values/${CLIENT}"
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
      }"

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

    echo "Copying ${src} -> ${dest}"
    mkdir -p "$(dirname "${dest}")"

    if [ -d "${src}" ]; then
      rsync -av --exclude='.git' "${src}/" "${dest}/"
    elif [ -f "${src}" ]; then
      rsync -av "${src}" "${dest}"
    fi
  done

  ##########################################
  # Commit & push child changes
  ##########################################
  if git status --porcelain | grep -q .; then
    git add -A
    git commit -m "Sync from template ${PARENT_REPO}@${PARENT_COMMIT} for ${CLIENT}"
    git push --set-upstream origin "${BRANCH}"

    ##########################################
    # Create PR
    ##########################################
    PR_JSON=$(jq -n \
      --arg title "Sync from template ${PARENT_COMMIT} → ${CLIENT}" \
      --arg head "${BRANCH}" \
      --arg base "main" \
      --arg body "Automated sync from ${PARENT_REPO} commit ${PARENT_COMMIT}" \
      '{title:$title, head:$head, base:$base, body:$body}')

    PR_RESPONSE=$(curl -s -X POST \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${CHILD_REPO}/pulls" \
      -d "${PR_JSON}")

    PR_NUMBER=$(echo "${PR_RESPONSE}" | jq -r '.number')

    echo "PR created for ${CLIENT}"

    ##########################################
    # Auto-merge (optional)
    ##########################################
    if [ "${AUTO_MERGE}" = "true" ]; then
      curl -s -X PUT \
        -H "Authorization: token ${TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${CHILD_REPO}/pulls/${PR_NUMBER}/merge" \
        -d '{"merge_method":"squash"}'
    fi
  else
    echo "No changes to sync for ${CLIENT}"
  fi

  cd "${PARENT_DIR}"
done

############################################
# Cleanup
############################################
rm -rf "${WORKDIR}"
cd "${ORIGINAL_PWD}"
