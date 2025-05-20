#!/bin/bash
# Optimized script for dry run migration of a subset of GitHub Enterprise repos
set -e

# Load .env
echo "[DEBUG] Loading ../config/.env..." | tee /dev/tty
source ../config/.env || { echo "[ERROR] ../config/.env not found" | tee /dev/tty; exit 1; }

# Validate variables
echo "[DEBUG] Validating environment variables..." | tee /dev/tty
: "${SOURCE_ORG:?Missing SOURCE_ORG}" "${DEST_ORG:?Missing DEST_ORG}" "${GH_PAT:?Missing GH_PAT}" "${GH_SOURCE_PAT:?Missing GH_SOURCE_PAT}" "${GH_SOURCE_HOST:?Missing GH_SOURCE_HOST}" "${DATA_DIR:?Missing DATA_DIR}" "${LOG_DIR:?Missing LOG_DIR}"

# Check tools
echo "[DEBUG] Checking for jq and gh..." | tee /dev/tty
command -v jq >/dev/null || { echo "[ERROR] jq required. Run: sudo apt-get install jq" | tee /dev/tty; exit 1; }
command -v gh >/dev/null || { echo "[ERROR] GitHub CLI required. Run: sudo apt-get install gh" | tee /dev/tty; exit 1; }

# Setup logging
echo "[DEBUG] Setting up logging..." | tee /dev/tty
mkdir -p "$LOG_DIR" || { echo "[ERROR] Cannot create $LOG_DIR" | tee /dev/tty; exit 1; }
chmod 755 "$LOG_DIR" || { echo "[ERROR] Cannot set permissions on $LOG_DIR" | tee /dev/tty; exit 1; }
LOG_FILE="$LOG_DIR/dry_run_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE" || { echo "[ERROR] Cannot write to $LOG_FILE" | tee /dev/tty; exit 1; }
chmod 644 "$LOG_FILE" || { echo "[ERROR] Cannot set permissions on $LOG_FILE" | tee /dev/tty; exit 1; }
echo "[INFO] Logging to $LOG_FILE" | tee /dev/tty "$LOG_FILE"

# Validate GitHub Enterprise auth
echo "[DEBUG] Validating GitHub Enterprise authentication ($GH_SOURCE_HOST)..." | tee /dev/tty "$LOG_FILE"
export GITHUB_HOST="$GH_SOURCE_HOST"
echo "$GH_SOURCE_PAT" | gh auth login --with-token 2>>"$LOG_FILE" || { echo "[ERROR] GitHub Enterprise auth failed. Check GH_SOURCE_PAT scopes (repo, admin:org)" | tee /dev/tty "$LOG_FILE"; exit 1; }
gh auth status | tee -a "$LOG_FILE" /dev/tty

# Validate GitHub.com auth
echo "[DEBUG] Validating GitHub.com authentication..." | tee /dev/tty "$LOG_FILE"
unset GITHUB_HOST
echo "$GH_PAT" | gh auth login --with-token 2>>"$LOG_FILE" || { echo "[ERROR] GitHub.com auth failed. Check GH_PAT scopes (repo, admin:org)" | tee /dev/tty "$LOG_FILE"; exit 1; }
gh auth status | tee -a "$LOG_FILE" /dev/tty

# Check gh-gei extension
echo "[DEBUG] Checking gh-gei extension..." | tee /dev/tty "$LOG_FILE"
if ! gh extension list | grep -q 'github/gh-gei'; then
  echo "[DEBUG] Installing gh-gei..." | tee /dev/tty "$LOG_FILE"
  gh extension install github/gh-gei 2>>"$LOG_FILE" || { echo "[ERROR] Failed to install gh-gei" | tee /dev/tty "$LOG_FILE"; exit 1; }
fi
echo "[INFO] gh-gei is installed" | tee /dev/tty "$LOG_FILE"

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
REPOS=$(jq -r '.[0:5] | .[].path' "$DATA_DIR/repo_inventory.json") # Subset: first 5 repos
if [[ -z "$REPOS" ]]; then
  echo "[INFO] No repositories in $DATA_DIR/repo_inventory.json. Exiting." | tee /dev/tty "$LOG_FILE"
  exit 0
fi
REPO_COUNT=$(wc -l <<< "$REPOS")
echo "[INFO] Selected $REPO_COUNT repositories for dry run" | tee /dev/tty "$LOG_FILE"

# Temporary directory
echo "[DEBUG] Creating temporary directory..." | tee /dev/tty "$LOG_FILE"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"; echo "[INFO] Cleaned up $TEMP_DIR" | tee /dev/tty "$LOG_FILE"' EXIT

# Generate and run migration for each repo
FAILURES=0
while IFS= read -r repo; do
  repo_name=$(basename "$repo")
  echo "[DEBUG] Processing $repo_name for dry run..." | tee /dev/tty "$LOG_FILE"

  # Generate migration script for single repo
  echo "[DEBUG] Generating migration script for $repo_name..." | tee /dev/tty "$LOG_FILE"
  SCRIPT_FILE="$TEMP_DIR/migration_$repo_name.sh"
  export GITHUB_HOST="$GH_SOURCE_HOST"
  if ! gh gei generate-script \
    --github-source-org "$SOURCE_ORG" \
    --github-target-org "$DEST_ORG" \
    --repo "$repo_name" \
    --output "$SCRIPT_FILE" 2>>"$LOG_FILE"; then
    echo "[ERROR] Failed to generate migration script for $repo_name" | tee /dev/tty "$LOG_FILE"
    ((FAILURES++))
    continue
  fi
  unset GITHUB_HOST

  # Validate script
  echo "[DEBUG] Validating migration script for $repo_name..." | tee /dev/tty "$LOG_FILE"
  if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo "[ERROR] Migration script $SCRIPT_FILE not found" | tee /dev/tty "$LOG_FILE"
    ((FAILURES++))
    continue
  fi

  # Run migration script
  echo "[DEBUG] Running dry run for $repo_name..." | tee /dev/tty "$LOG_FILE"
  if ! bash "$SCRIPT_FILE" 2>>"$LOG_FILE"; then
    echo "[ERROR] Dry run failed for $repo_name" | tee /dev/tty "$LOG_FILE"
    ((FAILURES++))
    continue
  fi

  echo "[INFO] Dry run completed for $repo_name" | tee /dev/tty "$LOG_FILE"
done <<< "$REPOS"

# Summary
echo "[INFO] Dry run completed. $((REPO_COUNT - FAILURES))/$REPO_COUNT repositories processed successfully." | tee /dev/tty "$LOG_FILE"
[[ $FAILURES -gt 0 ]] && echo "[WARNING] $FAILURES repositories failed. Check $LOG_FILE for details." | tee /dev/tty "$LOG_FILE"
echo "[INFO] Validate repositories in $DEST_ORG on GitHub.com" | tee /dev/tty "$LOG_FILE"
exit 0