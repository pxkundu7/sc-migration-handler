#!/bin/bash
# Simplified script to migrate GitLab CE repos to GitHub with terminal debug
set -e

# Load .env
echo "[DEBUG] Loading ../config/.env..." | tee /dev/tty
source ../config/.env || { echo "[ERROR] ../config/.env not found" | tee /dev/tty; exit 1; }

# Validate variables
echo "[DEBUG] Validating environment variables..." | tee /dev/tty
: "${SOURCE_ORG:?Missing SOURCE_ORG}" "${DEST_ORG:?Missing DEST_ORG}" "${GITLAB_PAT:?Missing GITLAB_PAT}" "${GH_PAT:?Missing GH_PAT}" "${GITLAB_HOST:?Missing GITLAB_HOST}" "${DATA_DIR:?Missing DATA_DIR}" "${LOG_DIR:?Missing LOG_DIR}"

# Check tools
echo "[DEBUG] Checking for jq and gh..." | tee /dev/tty
command -v jq >/dev/null || { echo "[ERROR] jq required. Run: sudo apt-get install jq" | tee /dev/tty; exit 1; }
command -v gh >/dev/null || { echo "[ERROR] GitHub CLI required. Run: sudo apt-get install gh" | tee /dev/tty; exit 1; }

# Setup logging
echo "[DEBUG] Setting up logging..." | tee /dev/tty
mkdir -p "$LOG_DIR" || { echo "[ERROR] Cannot create $LOG_DIR" | tee /dev/tty; exit 1; }
chmod 755 "$LOG_DIR" || { echo "[ERROR] Cannot set permissions on $LOG_DIR" | tee /dev/tty; exit 1; }
LOG_FILE="$LOG_DIR/migration_summary.log"
touch "$LOG_FILE" || { echo "[ERROR] Cannot write to $LOG_FILE" | tee /dev/tty; exit 1; }
chmod 644 "$LOG_FILE" || { echo "[ERROR] Cannot set permissions on $LOG_FILE" | tee /dev/tty; exit 1; }
echo "[INFO] Logging to $LOG_FILE" | tee /dev/tty "$LOG_FILE"

# Validate GitHub auth
echo "[DEBUG] Validating GitHub authentication..." | tee /dev/tty "$LOG_FILE"
echo "$GH_PAT" | gh auth login --with-token 2>>"$LOG_FILE" || { echo "[ERROR] GitHub auth failed. Check GH_PAT scopes (repo, admin:org)" | tee /dev/tty "$LOG_FILE"; exit 1; }
gh auth status | tee -a "$LOG_FILE" /dev/tty

# Validate GitLab PAT and get username
echo "[DEBUG] Validating GitLab PAT..." | tee /dev/tty "$LOG_FILE"
USER_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/user")
if ! echo "$USER_RESPONSE" | jq -e . >/dev/null 2>&1; then
  echo "[ERROR] Invalid GitLab PAT. Response: $USER_RESPONSE" | tee /dev/tty "$LOG_FILE"
  exit 1
fi
GITLAB_USER=$(echo "$USER_RESPONSE" | jq -r '.username')
echo "[INFO] GitLab PAT valid for user: $GITLAB_USER" | tee /dev/tty "$LOG_FILE"

# Validate repo_inventory.json
echo "[DEBUG] Checking repo_inventory.json..." | tee /dev/tty "$LOG_FILE"
if [[ ! -f "$DATA_DIR/repo_inventory.json" ]]; then
  echo "[ERROR] $DATA_DIR/repo_inventory.json not found" | tee /dev/tty "$LOG_FILE"
  exit 1
fi
if ! jq -e . "$DATA_DIR/repo_inventory.json" >/dev/null 2>&1; then
  echo "[ERROR] Invalid JSON in $DATA_DIR/repo_inventory.json" | tee /dev/tty "$LOG_FILE"
  exit 1
fi
REPOS=$(jq -r '.[].path' "$DATA_DIR/repo_inventory.json")
if [[ -z "$REPOS" ]]; then
  echo "[INFO] No repositories in $DATA_DIR/repo_inventory.json. Exiting." | tee /dev/tty "$LOG_FILE"
  exit 0
fi
REPO_COUNT=$(jq length "$DATA_DIR/repo_inventory.json")
echo "[INFO] Found $REPO_COUNT repositories to migrate" | tee /dev/tty "$LOG_FILE"

# Temporary directory
echo "[DEBUG] Creating temporary directory..." | tee /dev/tty "$LOG_FILE"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"; echo "[INFO] Cleaned up $TEMP_DIR" | tee /dev/tty "$LOG_FILE"' EXIT

# Migrate each repository
FAILURES=0
while IFS= read -r repo; do
  echo "[DEBUG] Processing $repo..." | tee /dev/tty "$LOG_FILE"
  repo_id=$(jq -r --arg path "$repo" '.[] | select(.path == $path) | .id' "$DATA_DIR/repo_inventory.json")
  http_url=$(jq -r --arg path "$repo" '.[] | select(.path == $path) | .http_url_to_repo' "$DATA_DIR/repo_inventory.json")
  repo_name=$(basename "$repo")

  # Fix GitLab URL with username and PAT
  fixed_url=$(echo "$http_url" | sed "s|http://[^/]*|${GITLAB_HOST}|" | sed "s|http://|http://${GITLAB_USER}:${GITLAB_PAT}@|")
  echo "[DEBUG] Using GitLab URL: $fixed_url" | tee /dev/tty "$LOG_FILE"

  # Check if GitHub repo exists
  echo "[DEBUG] Checking if $DEST_ORG/$repo_name exists on GitHub..." | tee /dev/tty "$LOG_FILE"
  if gh repo view "$DEST_ORG/$repo_name" >/dev/null 2>>"$LOG_FILE"; then
    echo "[INFO] GitHub repo $DEST_ORG/$repo_name exists, updating..." | tee /dev/tty "$LOG_FILE"
  else
    echo "[DEBUG] Creating GitHub repo $DEST_ORG/$repo_name..." | tee /dev/tty "$LOG_FILE"
    if ! gh repo create "$DEST_ORG/$repo_name" --private auto 2>>"$LOG_FILE"; then
      echo "[ERROR] Failed to create $DEST_ORG/$repo_name" | tee /dev/tty "$LOG_FILE"
      ((FAILURES++))
      continue
    fi
    echo "[INFO] Created GitHub repo $DEST_ORG/$repo_name" | tee /dev/tty "$LOG_FILE"
  fi

  # Clone GitLab repo
  echo "[DEBUG] Cloning $repo_name from GitLab..." | tee /dev/tty "$LOG_FILE"
  if ! git clone --mirror "$fixed_url" "$TEMP_DIR/$repo_name" 2>>"$LOG_FILE"; then
    echo "[ERROR] Failed to clone $repo_name from $fixed_url" | tee /dev/tty "$LOG_FILE"
    ((FAILURES++))
    continue
  fi

  # Push to GitHub
  echo "[DEBUG] Pushing $repo_name to GitHub..." | tee /dev/tty "$LOG_FILE"
  cd "$TEMP_DIR/$repo_name"
  if ! git push --mirror "https://$GH_PAT@github.com/$DEST_ORG/$repo_name.git"; then
    echo "[ERROR] Failed to push $repo_name to GitHub"
    cd - >/dev/null
    ((FAILURES++))
    continue
  fi
  cd - >/dev/null

  echo "[INFO] Successfully migrated $repo_name" | tee /dev/tty "$LOG_FILE"
done <<< "$REPOS"

# Summary
echo "[INFO] Migration completed. $((REPO_COUNT - FAILURES))/$REPO_COUNT repositories migrated successfully." | tee /dev/tty "$LOG_FILE"
[[ $FAILURES -gt 0 ]] && echo "[WARNING] $FAILURES repositories failed. Check $LOG_FILE for details." | tee /dev/tty "$LOG_FILE"
exit 0