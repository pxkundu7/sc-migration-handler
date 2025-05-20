#!/bin/bash
# Script to create 50 test repositories in GitLab CE under onprem-org group
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

# Verify jq is installed
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required. Installing jq..."
  sudo apt-get update && sudo apt-get install -y jq
fi

# Set Git user identity
git config --global user.name "Migration Bot"
git config --global user.email "migration@bot.local"
echo "Git identity configured: $(git config user.name) <$(git config user.email)>"

# Get group ID for onprem-org
echo "Fetching group ID for $SOURCE_ORG..."
GROUP_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/groups")
if [[ $(echo "$GROUP_RESPONSE" | jq -r 'type') != "array" ]]; then
  echo "Error: Failed to fetch groups. Response: $GROUP_RESPONSE"
  exit 1
fi

GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r --arg name "$SOURCE_ORG" '.[] | select(.name == $name) | .id')
if [[ -z "$GROUP_ID" ]]; then
  echo "Error: Group $SOURCE_ORG not found or inaccessible."
  echo "Please verify the group exists at $GITLAB_HOST and the GITLAB_PAT has access."
  exit 1
fi
echo "Found group $SOURCE_ORG with ID: $GROUP_ID"

# Create 50 repositories
for i in {1..50}; do
  REPO_NAME="repo-$i"
  echo "Creating repository $REPO_NAME in $SOURCE_ORG..."
  RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" -X POST \
    "$GITLAB_HOST/api/v4/projects?name=$REPO_NAME&namespace_id=$GROUP_ID")
  if [[ $(echo "$RESPONSE" | jq -r '.id') == "null" ]]; then
    echo "Error: Failed to create $REPO_NAME. Response: $RESPONSE"
    continue
  fi
  echo "Created $REPO_NAME"
done

# Populate repositories with sample data
for i in {1..50}; do
  REPO_NAME="repo-$i"
  echo "Populating $REPO_NAME..."
  if ! git clone "http://root:$GITLAB_PAT@localhost:8080/$SOURCE_ORG/$REPO_NAME.git"; then
    echo "Error: Failed to clone $REPO_NAME"
    continue
  fi
  cd "$REPO_NAME"
  echo "# Repo $i" > README.md
  git add . && git commit -m "Initial commit" || {
    echo "Error: Failed to commit in $REPO_NAME"
    cd .. && rm -rf "$REPO_NAME"
    continue
  }
  git push origin main || {
    echo "Error: Failed to push main branch in $REPO_NAME"
    cd .. && rm -rf "$REPO_NAME"
    continue
  }
  git checkout -b "feature-$i" || {
    echo "Error: Failed to create feature branch in $REPO_NAME"
    cd .. && rm -rf "$REPO_NAME"
    continue
  }
  echo "Feature $i" > feature.txt
  git add . && git commit -m "Add feature $i" || {
    echo "Error: Failed to commit feature branch in $REPO_NAME"
    cd .. && rm -rf "$REPO_NAME"
    continue
  }
  git push origin "feature-$i" || {
    echo "Error: Failed to push feature branch in $REPO_NAME"
    cd .. && rm -rf "$REPO_NAME"
    continue
  }
  # Create an issue
  ISSUE_RESPONSE=$(curl -s -H "Private-Token: $GITLAB_PAT" -X POST \
    "$GITLAB_HOST/api/v4/projects/$SOURCE_ORG%2F$REPO_NAME/issues?title=Issue%20$i&description=Test%20issue")
  if [[ $(echo "$ISSUE_RESPONSE" | jq -r '.id') == "null" ]]; then
    echo "Error: Failed to create issue for $REPO_NAME. Response: $ISSUE_RESPONSE"
  fi
  cd ..
  rm -rf "$REPO_NAME"
done

echo "Repository creation and population completed."