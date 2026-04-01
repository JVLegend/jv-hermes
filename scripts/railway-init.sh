#!/bin/bash
set -e

# Ensure /paperclip is writable (Railway volume mount may reset permissions)
if [ -w /paperclip ] || mkdir -p /paperclip 2>/dev/null; then
  echo "[railway-init] /paperclip is writable"
else
  echo "[railway-init] WARNING: /paperclip not writable, running as $(whoami)"
fi

VAULT_DIR="/paperclip/vault/SuperJV"
HERMES_HOME="${HOME}/.hermes"

echo "[railway-init] Setting up Hermes config..."
mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"

# Write minimal Hermes config for agent execution (no gateway, just hermes chat)
cat > "${HERMES_HOME}/config.yaml" << 'HERMESCONFIG'
model:
  default: kimi-k2.5
  provider: kimi-coding
  base_url: https://api.kimi.com/coding/v1
toolsets:
- hermes-cli
agent:
  max_turns: 60
  verbose: false
terminal:
  backend: local
  cwd: .
  timeout: 300
  persistent_shell: false
memory:
  memory_enabled: false
HERMESCONFIG

# Write .env with KIMI_API_KEY for hermes agent execution
if [ -n "${KIMI_API_KEY}" ]; then
  cat > "${HERMES_HOME}/.env" << ENVFILE
KIMI_API_KEY=${KIMI_API_KEY}
ENVFILE
  echo "[railway-init] KIMI_API_KEY written to .env"
fi

# Write SOUL.md (base64-encoded env var)
if [ -n "${HERMES_SOUL_CONTENT}" ]; then
  echo "${HERMES_SOUL_CONTENT}" | base64 -d > "${HERMES_HOME}/SOUL.md"
  echo "[railway-init] SOUL.md written."
fi

# Write jv-superpersona skill (base64-encoded env var)
if [ -n "${HERMES_SUPERPERSONA_CONTENT}" ]; then
  echo "${HERMES_SUPERPERSONA_CONTENT}" | base64 -d > "${HERMES_HOME}/skills/productivity/jv-superpersona/SKILL.md"
  echo "[railway-init] jv-superpersona skill written."
fi

echo "[railway-init] Cloning/updating SuperJV vault..."
if [ -d "${VAULT_DIR}/.git" ]; then
  cd "${VAULT_DIR}" && git pull --quiet && echo "[railway-init] Vault updated."
else
  if [ -z "${GITHUB_TOKEN}" ]; then
    echo "[railway-init] WARNING: GITHUB_TOKEN not set, skipping vault clone."
  else
    mkdir -p /paperclip/vault
    git clone --depth=1 "https://x-access-token:${GITHUB_TOKEN}@github.com/JVLegend/SuperJV.git" "${VAULT_DIR}" \
      && echo "[railway-init] Vault cloned."
  fi
fi

# Write config.json so CLI commands (bootstrap-ceo) can find it
INSTANCE_DIR="/paperclip/instances/default"
mkdir -p "${INSTANCE_DIR}"
if [ ! -f "${INSTANCE_DIR}/config.json" ]; then
  echo "[railway-init] Writing config.json..."
  PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-https://jv-paperclip-production.up.railway.app}"
  DB_MODE="embedded-postgres"
  if [ -n "${DATABASE_URL}" ]; then
    DB_MODE="postgres"
  fi
  cat > "${INSTANCE_DIR}/config.json" << PAPERCLIPCONFIG
{
  "\$meta": { "version": 1, "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "source": "onboard" },
  "server": {
    "host": "0.0.0.0",
    "port": 3100,
    "deploymentMode": "authenticated",
    "exposure": "public"
  },
  "auth": {
    "baseUrlMode": "explicit",
    "publicBaseUrl": "${PUBLIC_URL}"
  },
  "database": {
    "mode": "${DB_MODE}",
    "connectionString": "${DATABASE_URL:-}",
    "embeddedPostgresPort": 54329
  },
  "logging": {
    "mode": "file",
    "logDir": "/paperclip/instances/default/logs"
  }
}
PAPERCLIPCONFIG
fi

# ── Backup recovery files to persistent volume ──
RECOVERY_DIR="/paperclip/recovery"
mkdir -p "${RECOVERY_DIR}/hermes-gateway/skills/paperclip-bridge"
echo "[railway-init] Backing up recovery files to ${RECOVERY_DIR}..."

# Paperclip custom files
cp /app/Dockerfile.railway "${RECOVERY_DIR}/" 2>/dev/null || true
cp /app/scripts/railway-init.sh "${RECOVERY_DIR}/" 2>/dev/null || true
cp /app/scripts/learnings.mjs "${RECOVERY_DIR}/" 2>/dev/null || true
cp /app/scripts/learnings.sh "${RECOVERY_DIR}/" 2>/dev/null || true
cp /app/scripts/create-board-key.mjs "${RECOVERY_DIR}/" 2>/dev/null || true

# Hermes Gateway recovery files (SOULs, Dockerfile, entrypoint, skills, seed)
if [ -d /app/hermes-gateway-recovery ]; then
  cp -r /app/hermes-gateway-recovery/* "${RECOVERY_DIR}/hermes-gateway/" 2>/dev/null || true
  echo "[railway-init] Hermes Gateway recovery files copied."
fi

# Hermes config generated in this init
cp "${HERMES_HOME}/config.yaml" "${RECOVERY_DIR}/hermes-config.yaml" 2>/dev/null || true
cp "${HERMES_HOME}/SOUL.md" "${RECOVERY_DIR}/SOUL-paperclip.md" 2>/dev/null || true

# Snapshot env vars (redacted) for reference
env | grep -E "^(PAPERCLIP_|DATABASE_|KIMI_|GITHUB_|SETUP_|BETTER_AUTH|SERVE_UI|PORT)" \
  | sed 's/=.*/=<REDACTED>/' > "${RECOVERY_DIR}/env-vars-reference.txt" 2>/dev/null || true

# Timestamp
date -u +%Y-%m-%dT%H:%M:%SZ > "${RECOVERY_DIR}/last-backup.txt"
echo "[railway-init] Recovery files saved to ${RECOVERY_DIR}."

echo "[railway-init] Starting Paperclip..."
node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js &
SERVER_PID=$!

# Wait for embedded postgres + server to be ready, then run post-start setup
(
  echo "[railway-init] Waiting 25s for server + embedded postgres to initialize..."
  sleep 25
  cd /app
  PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-https://jv-paperclip-production.up.railway.app}"

  # Bootstrap CEO invite if needed
  echo "[railway-init] Running bootstrap-ceo..."
  node --import ./server/node_modules/tsx/dist/loader.mjs cli/src/index.ts auth bootstrap-ceo \
    --base-url "${PUBLIC_URL}" 2>&1 | sed 's/^/[bootstrap-ceo] /'

  # Create board API key for programmatic setup (if SETUP_API_KEY env is set)
  if [ -n "${SETUP_API_KEY}" ]; then
    echo "[railway-init] Creating board API key for programmatic setup..."
    node /app/scripts/create-board-key.mjs 2>&1
  fi

  # Initialize learnings table (self-improving agent system)
  echo "[railway-init] Initializing learnings DB..."
  node /app/scripts/learnings.mjs init 2>&1
) &

wait $SERVER_PID
