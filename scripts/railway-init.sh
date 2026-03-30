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
    "mode": "embedded-postgres",
    "embeddedPostgresPort": 54329
  },
  "logging": {
    "mode": "file",
    "logDir": "/paperclip/instances/default/logs"
  }
}
PAPERCLIPCONFIG
fi

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
    node -e "
      const { createHash } = require('crypto');
      const pg = require('pg');
      const client = new pg.Client('postgres://paperclip:paperclip@127.0.0.1:54329/paperclip');
      (async () => {
        await client.connect();
        const { rows: users } = await client.query(
          'SELECT user_id FROM instance_user_roles WHERE role = \\'instance_admin\\' LIMIT 1'
        );
        if (!users.length) { console.log('[setup-key] No admin user found'); process.exit(0); }
        const userId = users[0].user_id;
        const token = process.env.SETUP_API_KEY;
        const hash = createHash('sha256').update(token).digest('hex');
        // Upsert: delete old setup key, insert new
        await client.query('DELETE FROM board_api_keys WHERE name = \\'railway-setup\\'');
        await client.query(
          'INSERT INTO board_api_keys (id, user_id, name, key_hash, created_at) VALUES (gen_random_uuid(), \$1, \\'railway-setup\\', \$2, NOW())',
          [userId, hash]
        );
        console.log('[setup-key] Board API key created successfully for user ' + userId);
        await client.end();
      })().catch(e => { console.error('[setup-key] Error:', e.message); process.exit(0); });
    " 2>&1
  fi
) &

wait $SERVER_PID
