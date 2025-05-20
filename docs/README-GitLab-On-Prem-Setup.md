# GitLab CE On-Premises Setup on a Laptop

This document outlines the process of setting up and running an on-premises GitLab Community Edition (CE) instance on a laptop to act as a local server for the `sc-migration-handler` project. The setup supports the migration of repositories (`repo-1` to `repo-15`) from a GitLab group (`onprem-org`) to a GitHub organization (`pxkundu7-org`). By running GitLab CE locally, you can test and execute migrations in a controlled environment without external dependencies.

## Table of Contents

1. Overview
2. Prerequisites
3. Setup Instructions
4. Running GitLab CE
5. Configuring GitLab for Migration
6. Verifying the Setup
7. Troubleshooting
8. Best Practices
9. Shutting Down and Cleanup

## Overview

The `sc-migration-handler` project requires an on-premises GitLab CE instance to simulate a self-hosted GitLab environment. We use Docker to run GitLab CE on a laptop, exposing it at `http://localhost:8080`. The instance hosts the `onprem-org` group (ID: 2) with 15 repositories (`repo-1` to `repo-15`, IDs 16-30), managed by a bot user (`group_2_bot`). This setup allows testing of migration scripts (`inventory.sh`, `production_migration.sh`, `post_migration.sh`) locally before applying them to a production GitLab instance.

Key features of the setup:
- **Docker-based**: Ensures portability and consistency.
- **Local access**: Runs on `http://localhost:8080` for simplicity.
- **Pre-configured**: Includes group, repos, and user for immediate use.
- **Persistent data**: Uses Docker volumes to retain GitLab data across restarts.

## Prerequisites

### System Requirements
- **Operating System**: Linux (e.g., Ubuntu 22.04; tested in your environment). macOS/Windows with WSL2 also supported.
- **Hardware**:
  - 8 GB RAM (minimum; 16 GB recommended).
  - 20 GB free disk space for Docker images and GitLab data.
  - Multi-core CPU (e.g., 4 cores for performance).
- **Software**:
  - Docker: `docker` and `docker-compose` installed.
  - Git: For repository interactions.
  - Curl: For API testing.
  - Jq: For JSON parsing in scripts.
- **Network**:
  - Port 8080 free on localhost.
  - Internet access for pulling Docker images.

### Installation Commands
```bash
# Install Docker
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Install Git, Curl, Jq
sudo apt-get install -y git curl jq

# Verify installations
docker --version
git --version
curl --version
jq --version
```

### Assumptions
- The laptop has sufficient resources to run GitLab CE (a resource-intensive application).
- You have administrative privileges (`sudo`) for Docker setup.
- No other service is using port 8080.
- The GitLab CE instance is for testing, not production, and will be accessed locally.
- The `sc-migration-handler` project is cloned and configured (`../config/.env` exists).

## Setup Instructions

### Step 1: Clone sc-migration-handler
```bash
git clone https://github.com/pxkundu7/sc-migration-handler.git
cd sc-migration-handler
```

### Step 2: Create Docker Volume
To persist GitLab data (repos, configs, logs), create a Docker volume:
```bash
docker volume create gitlab-data
```

### Step 3: Run GitLab CE with Docker
Use a `docker-compose.yml` file to configure GitLab CE with the correct ports and volumes.

1. **Create `docker-compose.yml`**:
   ```bash
   nano docker-compose.yml
   ```
   Add:
   ```yaml
   version: '3.8'
   services:
     gitlab:
       image: gitlab/gitlab-ce:latest
       container_name: gitlab
       ports:
         - "8080:80"
       volumes:
         - gitlab-data:/var/opt/gitlab
       environment:
         GITLAB_OMNIBUS_CONFIG: |
           external_url 'http://localhost:8080'
           gitlab_rails['gitlab_shell_ssh_port'] = 2222
       restart: unless-stopped
   volumes:
     gitlab-data:
       external: true
   ```
   Save and exit.

2. **Start GitLab**:
   ```bash
   docker-compose up -d
   ```
   - This pulls the `gitlab/gitlab-ce:latest` image and starts the container.
   - Wait 2–5 minutes for GitLab to initialize (resource-dependent).

3. **Check Container Status**:
   ```bash
   docker ps
   ```
   - Expect:
     ```
     CONTAINER ID   IMAGE                   ...   PORTS                    NAMES
     <id>           gitlab/gitlab-ce:latest ...   0.0.0.0:8080->80/tcp     gitlab
     ```
   - View logs to monitor startup:
     ```bash
     docker logs gitlab
     ```

### Step 4: Access GitLab
1. **Open GitLab**:
   - Navigate to `http://localhost:8080` in a browser.
   - First-time setup prompts for a root password.

2. **Set Root Password**:
   - Enter a secure password (e.g., `GitLabRoot123!`).
   - Log in as `root` with the password.

3. **Create Bot User**:
   - Go to `Menu > Admin > Users > New User`.
   - Details:
     - Name: `Group 2 Bot`
     - Username: `group_2_bot`
     - Email: `bot@example.com`
     - Password: Set a secure password (e.g., `BotPass123!`).
   - Save and make the user an admin.

4. **Generate GitLab PAT**:
   - Log in as `group_2_bot`.
   - Go to `User Settings > Access Tokens`.
   - Create a token:
     - Name: `migration-token`
     - Scopes: `api`, `read_repository`, `write_repository`
     - Expiry: Set as needed (e.g., 1 month)
   - Copy the token (e.g., `glpat-TOKEN`).

## Running GitLab CE

### Start GitLab
If stopped, restart the container:
```bash
docker-compose start
```
- Or recreate if updates are needed:
  ```bash
  docker-compose up -d
  ```

### Monitor GitLab
- Check status:
  ```bash
  docker ps
  docker logs gitlab
  ```
- Verify access:
  ```bash
  curl -s http://localhost:8080 | grep -i gitlab
  ```
  - Expect HTML with “GitLab” in the title.

### Stop GitLab
To pause the instance:
```bash
docker-compose stop
```

## Configuring GitLab for Migration

### Step 1: Create Group and Repositories
1. **Create `onprem-org` Group**:
   - Log in as `root` or `group_2_bot_...`.
   - Go to `Menu > Groups > Create group`.
   - Details:
     - Group name: `onprem-org`
     - Visibility: Private
   - Save. Note the group ID (e.g., 2) from the group settings URL.

2. **Create Repositories**:
   Run `create_repos.sh` to create `repo-1` to `repo-15`:
   ```bash
   cd scripts
   ./create_repos.sh
   ```
   - This uses the GitLab API to create repos under `onprem-org`.
   - Verify:
     ```bash
     curl -s -H "Private-Token: $GITLAB_PAT" "http://localhost:8080/api/v4/projects?per_page=100" | jq -r '.[].path'
     ```
     - Expect: `repo-1` to `repo-15`.

3. **Populate Repositories**:
   Add sample commits and branches:
   ```bash
   ./generate_repo_history.sh
   ```
   - Verifies content:
     ```bash
     git clone http://group_2_bot@localhost:8080/onprem-org/repo-1.git
     cd repo-1
     git log --oneline
     cd ..
     rm -rf repo-1
     ```

### Step 2: Update .env
```bash
nano config/.env
```
Add:
```bash
SOURCE_ORG=onprem-org
DEST_ORG=pxkundu7
GITLAB_PAT=glpat-TOKEN
GH_PAT=ghp_...
GITLAB_HOST=http://localhost:8080
DATA_DIR=../data
LOG_DIR=../logs
```
- Secure the file:
  ```bash
  chmod 600 config/.env
  ```

### Step 3: Generate Inventory
```bash
./inventory.sh
```
- Creates `../data/repo_inventory.json`:
  ```bash
  cat ../data/repo_inventory.json | jq .
  ```
  - Example:
    ```json
    [
      {"id": 16, "path": "repo-1", "http_url_to_repo": "http://localhost:8080/onprem-org/repo-1.git"},
      ...
    ]
    ```

## Verifying the Setup

1. **GitLab Accessibility**:
   ```bash
   curl -s http://localhost:8080/api/v4/version | jq .
   ```
   - Expect version info (e.g., `17.0.0-ce`).

2. **Group and Repos**:
   ```bash
   source ../config/.env
   curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/groups/2" | jq -r '.name'
   ```
   - Expect: `onprem-org`.
   ```bash
   curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/projects?per_page=100" | jq -r '.[].path' | sort
   ```
   - Expect: `repo-1` to `repo-15`.

3. **PAT Validation**:
   ```bash
   curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/user" | jq -r '.username'
   ```
   - Expect: `group_2_bot`.

4. **Clone Test**:
   ```bash
   USER=$(curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/user" | jq -r '.username')
   git clone --mirror http://$USER:$GITLAB_PAT@localhost:8080/onprem-org/repo-1.git test-repo
   rm -rf test-repo
   ```
   - Should clone without prompting for a password.

## Troubleshooting

1. **Port 8080 in Use**:
   - Check:
     ```bash
     sudo netstat -tuln | grep 8080
     ```
   - Free the port:
     ```bash
     sudo kill -9 <pid>
     ```
   - Or change the port in `docker-compose.yml` (e.g., `8081:80`).

2. **GitLab Not Starting**:
   - Check logs:
     ```bash
     docker logs gitlab
     ```
   - Ensure enough memory:
     ```bash
     free -m
     ```
   - Restart:
     ```bash
     docker-compose restart
     ```

3. **Authentication Issues**:
   - Regenerate PAT if invalid:
     - Log in as `group_2_bot_...`.
     - Create new token with `api`, `read_repository`, `write_repository`.
     - Update `config/.env`.
   - Test:
     ```bash
     curl -s -H "Private-Token: $GITLAB_PAT" "$GITLAB_HOST/api/v4/projects"
     ```

4. **Slow Startup**:
   - GitLab CE is resource-heavy. Increase Docker resources or wait longer (5–10 minutes).
   - Check CPU/memory:
     ```bash
     docker stats
     ```

5. **Repo Creation Fails**:
   - Run `create_repos.sh` manually and check logs:
     ```bash
     bash -x ./create_repos.sh
     ```
   - Ensure `group_2_bot_...` has admin access to `onprem-org`.

## Best Practices

1. **Security**:
   - Use strong passwords for `root` and `group_2_bot_...`.
   - Restrict PAT scopes to only what’s needed.
   - Secure `.env`:
     ```bash
     chmod 600 config/.env
     ```

2. **Resource Management**:
   - Monitor Docker resource usage:
     ```bash
     docker stats --no-stream
     ```
   - Limit container resources in `docker-compose.yml`:
     ```yaml
     gitlab:
       ...
       deploy:
         resources:
           limits:
             cpus: '2'
             memory: 4G
     ```

3. **Backup**:
   - Backup GitLab data:
     ```bash
     docker exec gitlab gitlab-backup create
     ```
   - Store `/var/opt/gitlab/backups` from the `gitlab-data` volume.

4. **Logging**:
   - Enable GitLab logs for debugging:
     ```bash
     docker logs -f gitlab
     ```

5. **Testing**:
   - Test repo access before migration:
     ```bash
     git clone http://group_2_bot_...:$GITLAB_PAT@localhost:8080/onprem-org/repo-1.git
     ```

## Shutting Down and Cleanup

1. **Stop GitLab**:
   ```bash
   docker-compose down
   ```

2. **Remove Container and Image** (optional):
   ```bash
   docker-compose rm -f
   docker rmi gitlab/gitlab-ce:latest
   ```

3. **Remove Volume** (if no longer needed):
   ```bash
   docker volume rm gitlab-data
   ```
   - **Warning**: This deletes all GitLab data (repos, configs).

4. **Free Disk Space**:
   ```bash
   docker system prune -f
   ```

---

*Last updated by @pxkundu[https://github/pxkundu]: May 19, 2025, 09:12 PM EDT*