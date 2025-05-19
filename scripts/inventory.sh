#!/bin/bash
# Script to inventory repositories from on-prem GitHub Enterprise Server
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
: "${GH_SOURCE_PAT:?Missing GH_SOURCE_PAT}"
: "${GH_SOURCE_HOST:?Missing GH_SOURCE_HOST}"
: "${DATA_DIR:?Missing DATA_DIR}"

# Configure GitHub CLI for on-prem server
export GITHUB_HOST="$GH_SOURCE_HOST"
gh auth login --with-token <<< "$GH_SOURCE_PAT"

# List repositories and save to JSON
gh repo list "$SOURCE_ORG" --limit 1000 --json name,owner,url,diskUsage > "$DATA_DIR/repo_inventory.json"
echo "Repository inventory saved to $DATA_DIR/repo_inventory.json"

# Optional: Generate stats using gh-repo-stats extension
if gh extension list | grep -q gh-repo-stats; then
  gh repo-stats "$SOURCE_ORG" --output "$DATA_DIR/repo_stats.csv"
  echo "Repository stats saved to $DATA_DIR/repo_stats.csv"
fi
