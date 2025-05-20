#!/bin/bash
# Optimized script for post-migration tasks on GitHub.com
set -e

# Load .env
echo "[DEBUG] Loading ../config/.env..." | tee /dev/tty
source ../config/.env || { echo "[ERROR] ../config/.env not found" | tee /dev/tty; exit 1; }

# Validate variables
echo "[DEBUG] Validating environment variables..." | tee /dev/tty
: "${DEST_ORG:?Missing DEST_ORG}" "${GH_PAT:?Missing GH_PAT}" "${LOG_DIR:?Missing LOG_DIR}" "${DATA_DIR:?Missing DATA_DIR}"

# Check tools
echo "[DEBUG] Checking for jq and gh..." | tee /dev/tty
command -v jq >/dev/null || { echo "[ERROR] jq required. Run: sudo apt-get install jq" | tee /dev/tty; exit 1; }
command -v gh >/dev/null || { echo "[ERROR] GitHub CLI required. Run: sudo apt-get install gh" | tee /dev/tty; exit 1; }

# Setup logging
echo "[DEBUG] Setting up logging..." | tee /dev/tty
mkdir -p "$LOG_DIR" || { echo "[ERROR] Cannot create $LOG_DIR" | tee /dev/tty; exit 1; }
chmod 755 "$LOG_DIR" || { echo "[ERROR] Cannot set permissions on $LOG_DIR" | tee /dev/tty; exit 1; }
LOG_FILE="$LOG_DIR/post_migration_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE" || { echo "[ERROR] Cannot write to $LOG_FILE" | tee /dev/tty; exit 1; }
chmod 644 "$LOG_FILE" || { echo "[ERROR] Cannot set permissions on $LOG_FILE" | tee /dev/tty; exit 1; }
echo "[INFO] Logging to $LOG_FILE" | tee /dev/tty "$LOG_FILE"

# Validate GitHub.com auth
echo "[DEBUG] Validating GitHub.com authentication..." | tee /dev/tty "$LOG_FILE"
echo "$GH_PAT" | gh auth login --with-token 2>>"$LOG_FILE" || { echo "[ERROR] GitHub.com auth failed. Check GH_PAT scopes (repo, admin:org)" | tee /dev/tty "$LOG_FILE"; exit 1; }
gh auth status | tee -a "$LOG_FILE" /dev/tty

# Validate repo_inventory.json
echo "[DEBUG] Checking $DATA_DIR/repo_inventory.json..." | tee /dev/tty "$LOG_FILE"
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
REPO_COUNT=$(wc -l <<< "$REPOS")
echo "[INFO] Found $REPO_COUNT repositories for post-migration tasks" | tee /dev/tty "$LOG_FILE"

# Update repository visibility and create notification issues
FAILURES=0
declare -A JOB_PIDS
while IFS= read -r repo; do
  repo_name=$(basename "$repo")
  echo "[DEBUG] Processing $repo_name..." | tee /dev/tty "$LOG_FILE"
  
  # Run tasks in background for efficiency
  (
    # Update visibility to private
    echo "[DEBUG] Setting $DEST_ORG/$repo_name to private..." | tee -a "$LOG_FILE"
    if ! gh repo edit "$DEST_ORG/$repo_name" --visibility private 2>>"$LOG_FILE"; then
      echo "[ERROR] Failed to set $DEST_ORG/$repo_name to private" | tee -a "$LOG_FILE"
      exit 1
    fi

    # Create notification issue
    echo "[DEBUG] Creating notification issue for $DEST_ORG/$repo_name..." | tee -a "$LOG_FILE"
    if ! gh issue create --title "Migration Complete: Update Remotes" \
      --body "Migration to GitHub.com is complete. Update your remotes to: https://github.com/$DEST_ORG/$repo_name.git" \
      --repo "$DEST_ORG/$repo_name" 2>>"$LOG_FILE"; then
      echo "[ERROR] Failed to create notification issue for $DEST_ORG/$repo_name" | tee -a "$LOG_FILE"
      exit 1
    fi

    echo "[INFO] Successfully processed $repo_name" | tee -a "$LOG_FILE"
  ) &
  JOB_PIDS[$repo_name]=$!
  sleep 0.2 # Rate limit to avoid API abuse
done <<< "$REPOS"

# Wait for all jobs and track failures
for repo_name in "${!JOB_PIDS[@]}"; do
  if ! wait "${JOB_PIDS[$repo_name]}"; then
    echo "[ERROR] Post-migration tasks failed for $repo_name" | tee /dev/tty "$LOG_FILE"
    ((FAILURES++))
  fi
done

# Summary
echo "[INFO] Post-migration tasks completed. $((REPO_COUNT - FAILURES))/$REPO_COUNT repositories processed successfully." | tee /dev/tty "$LOG_FILE"
[[ $FAILURES -gt 0 ]] && echo "[WARNING] $FAILURES repositories failed. Check $LOG_FILE for details." | tee /dev/tty "$LOG_FILE"
exit 0