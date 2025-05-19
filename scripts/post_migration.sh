#!/bin/bash
# Script for post-migration tasks
set -e

# Load .env file
ENV_FILE="../config/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found"
  exit 1
fi
source "$ENV_FILE"

# Validate required variables
: "${DEST_ORG:?Missing DEST_ORG}"
: "${GH_PAT:?Missing GH_PAT}"
: "${LOG_DIR:?Missing LOG_DIR}"

# Log in to GitHub.com
gh auth login --with-token <<< "$GH_PAT"

# Update repository visibility (example: set to private)
for repo in $(gh repo list "$DEST_ORG" --json name --jq '.[].name'); do
  gh repo edit "$DEST_ORG/$repo" --visibility private >> "$LOG_DIR/post_migration.log"
done

# Notify developers (example: send email or webhook)
echo "Migration complete. Update remotes to https://github.com/$DEST_ORG/<repo>.git" >> "$LOG_DIR/post_migration.log"

echo "Post-migration tasks completed. Logs saved to $LOG_DIR/post_migration.log"
