#!/bin/bash
# Script to delete repositories repo-16 to repo-50 from onprem-org in GitLab CE
set -e

# Load .env file
ENV_FILE="../config/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: $ENV_FILE not found"
  exit 1
fi
source "$ENV_FILE"

# Validate required variables
: "${GITLAB_PAT:?Missing GITLAB_PAT}"
: "${GITLAB_HOST:?Missing GITLAB_HOST}"
: "${SOURCE_ORG:?Missing SOURCE_ORG}"
: "${LOG_DIR:?Missing LOG_DIR}"

# Verify jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Installing jq..."
  sudo apt-get update && sudo apt-get install -y jq
fi

# Log file
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/delete_repos_$(date +%Y%m%d_%H%M%S).log"
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

# Delete repositories repo-16 to repo-50
for i in {16..50}; do
  REPO_NAME="repo-$i"
  echo "Deleting $REPO_NAME..." | tee -a "$LOG_FILE"
  
  # Get project ID
  PROJECT_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/projects/$SOURCE_ORG%2F$REPO_NAME")
  PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.id')
  
  if [[ "$PROJECT_ID" == "null" ]]; then
    echo "Warning: $REPO_NAME does not exist. Skipping." | tee -a "$LOG_FILE"
    continue
  fi
  
  # Delete repository
  DELETE_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" -X DELETE "$GITLAB_HOST/api/v4/projects/$PROJECT_ID")
  if [[ -n "$DELETE_RESPONSE" && $(echo "$DELETE_RESPONSE" | jq -r '.message // empty') != "" ]]; then
    echo "Error: Failed to delete $REPO_NAME. Response: $DELETE_RESPONSE" | tee -a "$LOG_FILE"
    continue
  fi
  echo "Deleted $REPO_NAME" | tee -a "$LOG_FILE"
  sleep 1  # Prevent API rate limit issues
done

echo "Repository deletion completed. Logs saved to $LOG_FILE"
