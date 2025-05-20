#!/bin/bash
# Script to generate random history data (commits, branches, merge requests) for active GitLab CE repositories
set -e

# Load environment variables
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

# Set Git user identity
git config --global user.name "Migration Bot"
git config --global user.email "migration@bot.local"
echo "Git identity configured: $(git config user.name) <$(git config user.email)>"

# Create log directory
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/repo_history_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"
echo "Logging to $LOG_FILE"

# Get group ID for onprem-org
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

# Fetch active repositories
echo "Fetching active repositories for group $SOURCE_ORG..." | tee -a "$LOG_FILE"
PROJECTS_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/groups/$GROUP_ID/projects?per_page=100&archived=false")
if [[ $(echo "$PROJECTS_RESPONSE" | jq -r 'type') != "array" ]]; then
  echo "Error: Failed to fetch projects for group $SOURCE_ORG. Response: $PROJECTS_RESPONSE" | tee -a "$LOG_FILE"
  exit 1
fi

# Arrays for random data
COMMIT_MESSAGES=("Add new feature" "Fix bug in module" "Update documentation" "Refactor code" "Improve performance" "Add unit tests")
FILE_NAMES=("feature.c" "bugfix.py" "docs.md" "refactor.js" "config.yaml" "test.spec.ts")
BRANCH_PREFIXES=("feature" "bugfix" "docs" "refactor")

# Temporary directory for cloning
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR" | tee -a "$LOG_FILE"
trap 'rm -rf "$TEMP_DIR"; echo "Cleaned up $TEMP_DIR" | tee -a "$LOG_FILE"' EXIT

# Generate history for repositories repo-1 to repo-15
for i in {1..15}; do
  REPO_NAME="repo-$i"
  echo "Checking $REPO_NAME..." | tee -a "$LOG_FILE"

  # Check if repository exists
  PROJECT=$(echo "$PROJECTS_RESPONSE" | jq -r --arg path "$REPO_NAME" '.[] | select(.path == $path)')
  if [[ -z "$PROJECT" ]]; then
    echo "Warning: $REPO_NAME does not exist. Skipping." | tee -a "$LOG_FILE"
    continue
  fi
  PROJECT_ID=$(echo "$PROJECT" | jq -r '.id')
  CLONE_URL="http://root:$GITLAB_PAT@localhost:8080/$SOURCE_ORG/$REPO_NAME.git"

  # Clone repository into temp directory
  REPO_DIR="$TEMP_DIR/$REPO_NAME"
  if ! git clone "$CLONE_URL" "$REPO_DIR"; then
    echo "Error: Failed to clone $REPO_NAME" | tee -a "$LOG_FILE"
    continue
  fi
  cd "$REPO_DIR"

  # Initialize repository if empty
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "Initializing empty $REPO_NAME..." | tee -a "$LOG_FILE"
    echo "# $REPO_NAME" > README.md
    git add README.md
    git commit -m "Initial commit" || {
      echo "Error: Failed to initialize $REPO_NAME" | tee -a "$LOG_FILE"
      cd - >/dev/null
      continue
    }
    git push origin main || {
      echo "Error: Failed to push initial commit for $REPO_NAME" | tee -a "$LOG_FILE"
      cd - >/dev/null
      continue
    }
  fi

  # Generate random number of commits (3-10)
  NUM_COMMITS=$(shuf -i 3-10 -n 1)
  for ((j=1; j<=NUM_COMMITS; j++)); do
    FILE_NAME=${FILE_NAMES[$((RANDOM % ${#FILE_NAMES[@]}))]}
    COMMIT_MSG=${COMMIT_MESSAGES[$((RANDOM % ${#COMMIT_MESSAGES[@]}))]}
    echo "Commit $j: $COMMIT_MSG" > "$FILE_NAME"
    git add "$FILE_NAME"
    git commit -m "$COMMIT_MSG" || {
      echo "Error: Failed to commit in $REPO_NAME" | tee -a "$LOG_FILE"
      continue
    }
    git push origin main || {
      echo "Error: Failed to push main branch in $REPO_NAME" | tee -a "$LOG_FILE"
      continue
    }
    sleep 1
  done

  # Create random branches (1-3)
  NUM_BRANCHES=$(shuf -i 1-3 -n 1)
  for ((k=1; k<=NUM_BRANCHES; k++)); do
    BRANCH_PREFIX=${BRANCH_PREFIXES[$((RANDOM % ${#BRANCH_PREFIXES[@]}))]}
    BRANCH_NAME="$BRANCH_PREFIX-$i-$k"
    git checkout -b "$BRANCH_NAME" || {
      echo "Error: Failed to create branch $BRANCH_NAME in $REPO_NAME" | tee -a "$LOG_FILE"
      continue
    }
    FILE_NAME=${FILE_NAMES[$((RANDOM % ${#FILE_NAMES[@]}))]}
    COMMIT_MSG=${COMMIT_MESSAGES[$((RANDOM % ${#COMMIT_MESSAGES[@]}))]}
    echo "Branch commit: $COMMIT_MSG" > "$FILE_NAME"
    git add "$FILE_NAME"
    git commit -m "$COMMIT_MSG" || {
      echo "Error: Failed to commit to $BRANCH_NAME in $REPO_NAME" | tee -a "$LOG_FILE"
      continue
    }
    git push origin "$BRANCH_NAME" || {
      echo "Error: Failed to push $BRANCH_NAME in $REPO_NAME" | tee -a "$LOG_FILE"
      continue
    }

    # Create a merge request (50% chance)
    if [[ $((RANDOM % 2)) -eq 0 ]]; then
      MR_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" -X POST \
        "$GITLAB_HOST/api/v4/projects/$PROJECT_ID/merge_requests" \
        -d "source_branch=$BRANCH_NAME&target_branch=main&title=MR for $BRANCH_NAME&description=Auto-generated MR")
      if [[ $(echo "$MR_RESPONSE" | jq -r '.id') == "null" ]]; then
        echo "Error: Failed to create merge request for $BRANCH_NAME in $REPO_NAME. Response: $MR_RESPONSE" | tee -a "$LOG_FILE"
      else
        MR_ID=$(echo "$MR_RESPONSE" | jq -r '.id')
        echo "Created merge request $MR_ID for $BRANCH_NAME in $REPO_NAME" | tee -a "$LOG_FILE"

        # Merge the MR (50% chance)
        if [[ $((RANDOM % 2)) -eq 0 ]]; then
          MERGE_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" -X PUT \
            "$GITLAB_HOST/api/v4/projects/$PROJECT_ID/merge_requests/$MR_ID/merge")
          if [[ $(echo "$MERGE_RESPONSE" | jq -r '.id') == "null" ]]; then
            echo "Error: Failed to merge MR $MR_ID in $REPO_NAME. Response: $MERGE_RESPONSE" | tee -a "$LOG_FILE"
          else
            echo "Merged MR $MR_ID in $REPO_NAME" | tee -a "$LOG_FILE"
            git checkout main
            git pull origin main
            git push origin main
          fi
        fi
      fi
    fi
    git checkout main
    sleep 1
  done

  cd - >/dev/null
  rm -rf "$REPO_DIR"
  echo "Completed history generation for $REPO_NAME" | tee -a "$LOG_FILE"
  sleep 2
done

echo "Repository history generation completed. Logs saved to $LOG_FILE" | tee -a "$LOG_FILE"