#!/bin/bash
set -e

VAULT_DIR="/paperclip/vault/SuperJV"
HERMES_HOME="${HOME}/.hermes"

echo "[railway-init] Setting up Hermes config..."
mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"

# Write minimal Hermes config for agent execution (no gateway, just hermes chat)
cat > "${HERMES_HOME}/config.yaml" << 'HERMESCONFIG'
model:
  default: kimi-k2.5
  provider: kimi-coding
  base_url: https://api.moonshot.ai/v1
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
  cat > "${INSTANCE_DIR}/config.json" << PAPERCLIPCONFIG
{
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
    "mode": "embedded-postgres",
    "embeddedPostgresPort": 54329
  }
}
PAPERCLIPCONFIG
fi

echo "[railway-init] Starting Paperclip..."
node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js &
SERVER_PID=$!

# Wait for embedded postgres + server to be ready, then bootstrap CEO if needed
(
  echo "[railway-init] Waiting 25s for server + embedded postgres to initialize..."
  sleep 25
  cd /app
  PUBLIC_URL="${PAPERCLIP_PUBLIC_URL:-https://jv-paperclip-production.up.railway.app}"
  echo "[railway-init] Running bootstrap-ceo..."
  node --import ./server/node_modules/tsx/dist/loader.mjs cli/src/index.ts auth bootstrap-ceo \
    --base-url "${PUBLIC_URL}" 2>&1 | sed 's/^/[bootstrap-ceo] /'
) &

wait $SERVER_PID
