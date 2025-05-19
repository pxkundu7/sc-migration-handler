#!/bin/bash
# Script to perform production migration
set -e

# Load .env file
ENV_FILE="../config/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found"
  exit 1
fi
source "$ENV_FILE"

# Validate required variables
: "${SOURCE_ORG:?Missing SOURCE_ORG}"
: "${DEST_ORG:?Missing DEST_ORG}"
: "${GH_PAT:?Missing GH_PAT}"
: "${GH_SOURCE_PAT:?Missing GH_SOURCE_PAT}"
: "${GH_SOURCE_HOST:?Missing GH_SOURCE_HOST}"
: "${DATA_DIR:?Missing DATA_DIR}"
: "${LOG_DIR:?Missing LOG_DIR}"

# Configure GitHub CLI for on-prem
export GITHUB_HOST="$GH_SOURCE_HOST"
gh auth login --with-token <<< "$GH_SOURCE_PAT"

# Switch to GitHub.com
unset GITHUB_HOST
gh auth login --with-token <<< "$GH_PAT"

# Generate full migration script
gh gei generate-script \
  --github-source-org "$SOURCE_ORG" \
  --github-target-org "$DEST_ORG" \
  --output "$DATA_DIR/full_migration_script.sh"

# Run migration
bash "$DATA_DIR/full_migration_script.sh" >> "$LOG_DIR/migration.log"

# Validate migration
for repo in $(gh repo list "$DEST_ORG" --json name --jq '.[].name'); do
  echo "Validating $repo..." >> "$LOG_DIR/validation.log"
  gh repo view "$DEST_ORG/$repo" >> "$LOG_DIR/validation.log"
done

echo "Production migration completed. Logs saved to $LOG_DIR/migration.log and $LOG_DIR/validation.log"
