#!/usr/bin/env bash
set -euo pipefail

CLIENT="$1"
AUTO_MERGE="$2"
ORG="$3"           # e.g., codekarma
PARENT_REPO="$4"   # e.g., codekarma/service-template
TOKEN="$5"

# Configuration: which paths to sync from parent -> child.
# Adjust these to fit what you want copied for each client.
SYNC_PATHS=(
  "charts"
  "applications/all-apps.yaml"
  "values/${CLIENT}"
)

TIMESTAMP=$(date +"%Y%m%d%H%M%S")
BRANCH="sync/${CLIENT}/${TIMESTAMP}"
TMPDIR=$(mktemp -d)
PARENT_DIR="${TMPDIR}/parent"
CHILD_DIR="${TMPDIR}/child"
CHILD_REPO="${ORG}/${CLIENT}-charts"   # adjust naming convention

echo "Syncing client: $CLIENT -> repo: $CHILD_REPO"
echo "Working in $TMPDIR"

# 1) clone parent (already checked out in workflow's workspace - but do it here for safety)
git clone --depth 1 "https://x-access-token:${TOKEN}@github.com/${PARENT_REPO}.git" "${PARENT_DIR}"
cd "${PARENT_DIR}" || exit 1
PARENT_COMMIT=$(git rev-parse --short HEAD)

# 2) clone child repo
git clone "https://x-access-token:${TOKEN}@github.com/${CHILD_REPO}.git" "${CHILD_DIR}"
cd "${CHILD_DIR}" || exit 1

# Create a new branch
git checkout -b "${BRANCH}"

# 3) copy files (only those in SYNC_PATHS)
for p in "${SYNC_PATHS[@]}"; do
  src="${PARENT_DIR}/${p}"
  dest="${CHILD_DIR}/${p}"
  echo "Copying $src -> $dest"
  # Ensure destination directory exists
  mkdir -p "$(dirname "$dest")"
  # Use rsync to copy (preserves structure, excludes .git)
  rsync -av --delete --exclude='.git' "$src" "$dest"
done

# 4) commit if changes exist
cd "${CHILD_DIR}" || exit 1
if git status --porcelain | grep .; then
  echo "Changes detected; committing..."
  git add -A
  git commit -m "Sync from template ${PARENT_REPO}@${PARENT_COMMIT} for client ${CLIENT}"
  git push --set-upstream origin "${BRANCH}"

  # 5) Create PR using GitHub CLI or API
  PR_TITLE="Sync from template: ${PARENT_COMMIT} -> ${CLIENT}"
  PR_BODY="Automated sync from ${PARENT_REPO} commit ${PARENT_COMMIT}.\n\nFiles copied:\n$(git --no-pager diff --name-status origin/$(git rev-parse --abbrev-ref HEAD)..HEAD || true)"

  # Use GitHub API to create PR
  API_JSON=$(jq -n \
    --arg title "$PR_TITLE" \
    --arg head "$BRANCH" \
    --arg base "main" \
    --arg body "$PR_BODY" \
    '{title:$title, head:$head, base:$base, body:$body}')
  CREATE_PR_URL="https://api.github.com/repos/${CHILD_REPO}/pulls"
  PR_RESPONSE=$(curl -s -X POST -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github+json" \
    "${CREATE_PR_URL}" -d "${API_JSON}")

  PR_URL=$(echo "${PR_RESPONSE}" | jq -r '.html_url')
  PR_NUMBER=$(echo "${PR_RESPONSE}" | jq -r '.number')

  echo "Created PR: ${PR_URL}"

  # Optionally attempt to auto-merge (if allowed)
  if [ "${AUTO_MERGE}" = "true" ]; then
    echo "Attempting to auto-merge PR #${PR_NUMBER}"
    MERGE_URL="https://api.github.com/repos/${CHILD_REPO}/pulls/${PR_NUMBER}/merge"
    MERGE_RESP=$(curl -s -X PUT -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github+json" \
      "${MERGE_URL}" -d '{"merge_method":"squash"}')
    echo "Merge response: ${MERGE_RESP}"
  fi

else
  echo "No changes to sync for ${CLIENT} (parent commit ${PARENT_COMMIT}). Exiting."
fi

# 6) cleanup
rm -rf "${TMPDIR}"
