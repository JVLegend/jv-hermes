#!/bin/bash
set -e

HERMES_HOME="${HOME}/.hermes"
mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"
mkdir -p "${HERMES_HOME}/skills/productivity/paperclip-bridge"

# Copy paperclip-bridge skill from Docker image
if [ -d /hermes-skills/paperclip-bridge ]; then
  cp /hermes-skills/paperclip-bridge/* "${HERMES_HOME}/skills/productivity/paperclip-bridge/"
  chmod +x "${HERMES_HOME}/skills/productivity/paperclip-bridge/pcp.sh"
  echo "[hermes-gateway] paperclip-bridge skill installed."
fi

echo "[hermes-gateway] Writing config..."
cat > "${HERMES_HOME}/config.yaml" << HERMESCONFIG
model:
  default: kimi-k2.5
  provider: kimi-coding
  base_url: ${KIMI_BASE_URL:-https://api.kimi.com/coding/v1}
toolsets:
- hermes-cli
agent:
  max_turns: 60
  verbose: false
  reasoning_effort: medium
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 2200
  user_char_limit: 1375
delegation:
  max_iterations: 50
  default_toolsets:
  - terminal
  - file
  - web
skills:
  auto_load:
  - jv-superpersona
  - paperclip-bridge
platforms:
  telegram:
    enabled: true
    token: "${TELEGRAM_BOT_TOKEN}"
platform_toolsets:
  telegram:
  - browser
  - clarify
  - delegation
  - file
  - memory
  - session_search
  - skills
  - terminal
  - web
group_sessions_per_user: true
HERMESCONFIG

# Write .env for KIMI_API_KEY (hermes reads from ~/.hermes/.env)
cat > "${HERMES_HOME}/.env" << ENVFILE
KIMI_API_KEY=${KIMI_API_KEY}
PAPERCLIP_API_URL=${PAPERCLIP_API_URL:-https://jv-paperclip-production.up.railway.app/api}
PAPERCLIP_API_KEY=${PAPERCLIP_API_KEY:-pcp_board_setup_bc5dce235ce5166620bd3d15061636c87fa1be6a3d4298a6}
PAPERCLIP_COMPANY_ID=${PAPERCLIP_COMPANY_ID:-6da87f11-6a27-4627-b101-924d5a161f6e}
ENVFILE

# SOUL.md — orchestrator persona (base64-encoded)
if [ -n "${HERMES_SOUL_CONTENT}" ]; then
  echo "${HERMES_SOUL_CONTENT}" | base64 -d > "${HERMES_HOME}/SOUL.md"
else
  echo "Voce é Hermes, o orquestrador central de JV. Responda em português, seja direto." > "${HERMES_HOME}/SOUL.md"
fi

# jv-superpersona skill (base64-encoded)
if [ -n "${HERMES_SUPERPERSONA_CONTENT}" ]; then
  echo "${HERMES_SUPERPERSONA_CONTENT}" | base64 -d > "${HERMES_HOME}/skills/productivity/jv-superpersona/SKILL.md"
fi

echo "[hermes-gateway] Ready. SOUL=$(test -f ${HERMES_HOME}/SOUL.md && echo 'ok' || echo 'missing') Skills=$(ls ${HERMES_HOME}/skills/productivity/ 2>/dev/null | tr '\n' ',')"
exec hermes gateway run --replace
