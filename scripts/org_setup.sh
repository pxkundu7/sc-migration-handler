#!/bin/bash
# Script to configure GitHub.com organization
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

# Create teams
gh api -X POST \
  -H "Accept: application/vnd.github+json" \
  "/orgs/$DEST_ORG/teams" \
  -f name="dev-team" \
  -f description="Development Team" >> "$LOG_DIR/org_setup.log"

# Set default repository visibility to private
gh api -X PATCH \
  -H "Accept: application/vnd.github+json" \
  "/orgs/$DEST_ORG" \
  -f default_repository_permission="none" \
  -f members_can_create_repos=false >> "$LOG_DIR/org_setup.log"

echo "Organization $DEST_ORG configured. Logs saved to $LOG_DIR/org_setup.log"
