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
set -Eeuo pipefail

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
APP_PORT="${APP_PORT:-3000}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=15"

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

remote "PROJECT_PATH='${PROJECT_PATH}' DEPLOY_BRANCH='${DEPLOY_BRANCH}' APP_PORT='${APP_PORT}' bash -s" <<'DEPLOY_SCRIPT'
set -Eeuo pipefail

DOCKER_COMPOSE="docker compose -f docker/docker-compose.yml"
mkdir -p "${PROJECT_PATH}/log"
MIGRATE_LOG="${PROJECT_PATH}/log/deploy-migrate.log"
LOCAL=""
_ROLLBACK_IN_PROGRESS=""

rollback() {
  if [[ -n "${_ROLLBACK_IN_PROGRESS}" ]]; then
    echo "[deploy] ERROR: Rollback already in progress — aborting to prevent loop"
    exit 1
  fi
  _ROLLBACK_IN_PROGRESS="1"

  if [[ -z "${LOCAL}" ]]; then
    echo "[deploy] ERROR: Deploy failed before snapshot — cannot rollback automatically"
    echo "[deploy] Manual intervention required."
    exit 1
  fi

  echo "[deploy] ERROR: Deploy failed — rolling back to ${LOCAL:0:7}..."
  git reset --hard "${LOCAL}"
  echo "[deploy] Restoring previous container image..."
  IMAGE_TAG="${LOCAL:0:12}" ${DOCKER_COMPOSE} up -d --force-recreate app jobs discord-bot
  echo "[deploy] Rollback completed. Manual verification recommended."
  exit 1
}
trap rollback ERR

cd "${PROJECT_PATH}"

# Ensure storage directory has correct permissions for Docker bind mount.
# Git may reset permissions, and the container needs write access as 'rails' user.
mkdir -p "${PROJECT_PATH}/storage"
chmod 777 "${PROJECT_PATH}/storage"

echo "[deploy] Fetching latest changes..."
git fetch origin "${DEPLOY_BRANCH}"
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/${DEPLOY_BRANCH}")
IMAGE_TAG="${LOCAL:0:12}"

if [[ "${LOCAL}" == "${REMOTE}" ]]; then
  echo "[deploy] Already up to date (${LOCAL:0:7}). Nothing to deploy."
  exit 0
fi

echo "[deploy] Updating: ${LOCAL:0:7} → ${REMOTE:0:7}"
git checkout "${DEPLOY_BRANCH}"
git pull origin "${DEPLOY_BRANCH}"

# Rebuild and restart only if Dockerfile or Gemfile changed
if git rev-parse --verify ORIG_HEAD > /dev/null 2>&1; then
  CHANGED=$(git diff --name-only ORIG_HEAD HEAD)
  NEEDS_REBUILD=false
else
  CHANGED=""
  NEEDS_REBUILD=true
fi

for pattern in Dockerfile Dockerfile.python Gemfile Gemfile.lock docker/; do
  if echo "${CHANGED}" | grep -q "^${pattern}"; then
    NEEDS_REBUILD=true
    break
  fi
done

if [[ "${NEEDS_REBUILD}" == "true" ]]; then
  echo "[deploy] Docker/Gemfile changes detected — full rebuild..."
  IMAGE_TAG="${IMAGE_TAG}" ${DOCKER_COMPOSE} build --no-cache
else
  echo "[deploy] Code-only changes — fast rebuild..."
  IMAGE_TAG="${IMAGE_TAG}" ${DOCKER_COMPOSE} build
fi

echo "[deploy] Running migrations..."
if ! ${DOCKER_COMPOSE} run --rm --entrypoint bin/rails app db:migrate >"${MIGRATE_LOG}" 2>&1; then
  echo "[deploy] ERROR: Migration failed — see ${MIGRATE_LOG} for details"
  cat "${MIGRATE_LOG}"
  rollback
fi

echo "[deploy] Restarting services and waiting for health..."
# start_period=15s + interval=10s + retries=3 → máx ~45s de health check
# --wait-timeout 90 cobre com folga (startup Rails ~10s + 45s = ~55s)
IMAGE_TAG="${IMAGE_TAG}" ${DOCKER_COMPOSE} up -d --wait --wait-timeout 90 app jobs discord-bot

echo "[deploy] Cleaning up old images..."
docker image prune -f --filter "until=24h"
docker builder prune -f --filter "until=24h"

echo "[deploy] Deploy complete: ${REMOTE:0:7}"
DEPLOY_SCRIPT

log "Deploy finished successfully."
