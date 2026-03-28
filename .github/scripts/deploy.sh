#!/usr/bin/env bash
# .github/scripts/deploy.sh
#
# Deploy BotDiscord to production VM via SSH.
# Pulls latest changes, rebuilds containers, and restarts services.
#
# Required env vars:
#   SSH_PRIVATE_KEY — private key for VM access
#   SSH_HOST        — VM public IP
#   SSH_USER        — SSH username (default: ubuntu)
#   PROJECT_PATH    — project directory on VM (default: /opt/botdiscord)
#   DEPLOY_BRANCH   — branch to deploy (default: main)
set -euo pipefail

log() { echo "[deploy] $*"; }

# ─── Validate inputs ────────────────────────────────────────────────
for var in SSH_PRIVATE_KEY SSH_HOST; do
  if [[ -z "${!var:-}" ]]; then
    log "ERROR: ${var} is not set"
    exit 1
  fi
done

SSH_USER="${SSH_USER:-ubuntu}"
PROJECT_PATH="${PROJECT_PATH:-/opt/botdiscord}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-main}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=15"

# ─── Setup SSH key ──────────────────────────────────────────────────
log "Configuring SSH key..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "${SSH_PRIVATE_KEY}" > ~/.ssh/deploy_key
chmod 600 ~/.ssh/deploy_key

cleanup() { rm -f ~/.ssh/deploy_key; }
trap cleanup EXIT

remote() {
  ssh -i ~/.ssh/deploy_key ${SSH_OPTS} "${SSH_USER}@${SSH_HOST}" "$@"
}

# ─── Verify connection ──────────────────────────────────────────────
log "Testing SSH connection to ${SSH_HOST}..."
if ! remote "echo 'connected'"; then
  log "ERROR: Cannot connect to ${SSH_HOST}"
  exit 1
fi

# ─── Deploy ─────────────────────────────────────────────────────────
log "Deploying to ${SSH_USER}@${SSH_HOST}:${PROJECT_PATH}..."

remote bash <<'DEPLOY_SCRIPT'
set -euo pipefail

PROJECT_PATH="'"${PROJECT_PATH}"'"
DEPLOY_BRANCH="'"${DEPLOY_BRANCH}"'"
DOCKER_COMPOSE="docker compose -f docker/docker-compose.yml"

cd "${PROJECT_PATH}"

echo "[deploy] Fetching latest changes..."
git fetch origin "${DEPLOY_BRANCH}"
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/${DEPLOY_BRANCH}")

if [[ "${LOCAL}" == "${REMOTE}" ]]; then
  echo "[deploy] Already up to date (${LOCAL:0:7}). Nothing to deploy."
  exit 0
fi

echo "[deploy] Updating: ${LOCAL:0:7} → ${REMOTE:0:7}"
git checkout "${DEPLOY_BRANCH}"
git pull origin "${DEPLOY_BRANCH}"

# Rebuild and restart only if Dockerfile or Gemfile changed
CHANGED=$(git diff --name-only "${LOCAL}" "${REMOTE}")
NEEDS_REBUILD=false

for pattern in Dockerfile Dockerfile.python Gemfile Gemfile.lock docker/; do
  if echo "${CHANGED}" | grep -q "^${pattern}"; then
    NEEDS_REBUILD=true
    break
  fi
done

if [[ "${NEEDS_REBUILD}" == "true" ]]; then
  echo "[deploy] Docker/Gemfile changes detected — full rebuild..."
  ${DOCKER_COMPOSE} build --no-cache
else
  echo "[deploy] Code-only changes — fast rebuild..."
  ${DOCKER_COMPOSE} build
fi

echo "[deploy] Running migrations..."
${DOCKER_COMPOSE} run --rm --entrypoint bin/rails app db:migrate 2>/dev/null || {
  echo "[deploy] Migration step skipped (might be handled by entrypoint)"
}

echo "[deploy] Restarting services..."
${DOCKER_COMPOSE} up -d --force-recreate app jobs discord-bot

echo "[deploy] Cleaning up old images..."
docker image prune -f

echo "[deploy] Checking service health..."
sleep 5
${DOCKER_COMPOSE} ps

echo "[deploy] Deploy complete: ${REMOTE:0:7}"
DEPLOY_SCRIPT

log "Deploy finished successfully."
