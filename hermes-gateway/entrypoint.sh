#!/bin/bash
set -e

HERMES_HOME="${HOME}/.hermes"
mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"

echo "[hermes-gateway] Writing config..."
cat > "${HERMES_HOME}/config.yaml" << HERMESCONFIG
model:
  default: kimi-k2.5
  provider: kimi-coding
  base_url: https://api.moonshot.ai/v1
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

# Write gateway config with Telegram bot token
cat > "${HERMES_HOME}/gateway.yaml" << GWCONFIG
telegram:
  bot_token: "${TELEGRAM_BOT_TOKEN}"
  allowed_users: []
port: ${PORT:-8080}
GWCONFIG

echo "[hermes-gateway] Starting Hermes gateway on port ${PORT:-8080}..."
exec hermes gateway run --config "${HERMES_HOME}/gateway.yaml"
