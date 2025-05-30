#!/bin/bash
# Script to inventory active GitLab CE repositories
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
: "${GITLAB_PAT:?Missing GITLAB_PAT}"
: "${GITLAB_HOST:?Missing GITLAB_HOST}"
: "${DATA_DIR:?Missing DATA_DIR}"
: "${LOG_DIR:?Missing LOG_DIR}"

# Verify jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Installing jq..."
  sudo apt-get update && sudo apt-get install -y jq
fi

# Create log directory
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/inventory_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"
echo "Logging to $LOG_FILE"

# Get group ID for SOURCE_ORG
echo "Fetching group ID for $SOURCE_ORG..." | tee -a "$LOG_FILE"
GROUP_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/groups")
if [[ $(echo "$GROUP_RESPONSE" | jq -r 'type') != "array" ]]; then
  echo "Error: Failed to fetch groups. Response: $GROUP_RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi

GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r --arg name "$SOURCE_ORG" '.[] | select(.name == $name) | .id')
if [[ -z "$GROUP_ID" ]]; then
  echo "Error: Group $SOURCE_ORG not found or inaccessible." | tee -a "$LOG_FILE"
  exit 1
fi
echo "Found group $SOURCE_ORG with ID: $GROUP_ID" | tee -a "$LOG_FILE"

# List active, non-archived repositories
echo "Fetching active repositories for group $SOURCE_ORG..." | tee -a "$LOG_FILE"
PROJECTS_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/groups/$GROUP_ID/projects?per_page=100&archived=false")
if [[ $(echo "$PROJECTS_RESPONSE" | jq -r 'type') != "array" ]]; then
  echo "Error: Failed to fetch projects for group $SOURCE_ORG. Response: $PROJECTS_RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi

# Filter and save inventory
echo "$PROJECTS_RESPONSE" | jq '[.[] | select(.archived == false) | {id, path, name, http_url_to_repo}]' > "$DATA_DIR/repo_inventory.json"
if [[ ! -s "$DATA_DIR/repo_inventory.json" ]]; then
  echo "Error: repo_inventory.json is empty" | tee -a "$LOG_FILE"
  exit 1
fi
REPO_COUNT=$(jq length "$DATA_DIR/repo_inventory.json")
echo "Repository inventory saved to $DATA_DIR/repo_inventory.json with $REPO_COUNT repositories" | tee -a "$LOG_FILE"