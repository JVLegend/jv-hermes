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

# Detect LLM provider: Gemini (default) or Kimi (fallback)
if [ -n "${GOOGLE_API_KEY}" ]; then
  export LLM_MODEL="${HERMES_MODEL:-gemini-2.0-flash}"
  export LLM_PROVIDER="google"
  export LLM_BASE_URL="${GOOGLE_BASE_URL:-https://generativelanguage.googleapis.com/v1beta}"
  export HERMES_MODEL="${LLM_MODEL}"
  export HERMES_PROVIDER="google"
  export HERMES_INFERENCE_PROVIDER="gemini"
  echo "[hermes-gateway] LLM: Gemini (${LLM_MODEL})"
elif [ -n "${KIMI_API_KEY}" ]; then
  export LLM_MODEL="${HERMES_MODEL:-kimi-k2.5}"
  export LLM_PROVIDER="kimi-coding"
  export LLM_BASE_URL="${KIMI_BASE_URL:-https://api.kimi.com/coding/v1}"
  export HERMES_MODEL="${LLM_MODEL}"
  export HERMES_PROVIDER="kimi-coding"
  export HERMES_INFERENCE_PROVIDER="kimi"
  echo "[hermes-gateway] LLM: Kimi (${LLM_MODEL})"
else
  echo "[hermes-gateway] ERRO: nenhuma API key encontrada (GOOGLE_API_KEY ou KIMI_API_KEY)"
  exit 1
fi

echo "[hermes-gateway] Writing config..."
cat > "${HERMES_HOME}/config.yaml" << HERMESCONFIG
model:
  default: ${LLM_MODEL}
  provider: ${LLM_PROVIDER}
  base_url: ${LLM_BASE_URL}
toolsets:
- hermes-cli
agent:
  max_turns: 60
  verbose: false
  reasoning_effort: medium
  language: pt-br
  system_suffix: "IMPORTANTE: Sempre pense e responda em português brasileiro. Todos os seus pensamentos internos, raciocínios e respostas devem ser em pt-BR."
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

# Write .env for API keys (hermes reads from ~/.hermes/.env)
cat > "${HERMES_HOME}/.env" << ENVFILE
GOOGLE_API_KEY=${GOOGLE_API_KEY}
KIMI_API_KEY=${KIMI_API_KEY}
PAPERCLIP_API_URL=${PAPERCLIP_API_URL:-https://jv-paperclip-production.up.railway.app/api}
PAPERCLIP_API_KEY=${PAPERCLIP_API_KEY:-pcp_board_setup_bc5dce235ce5166620bd3d15061636c87fa1be6a3d4298a6}
PAPERCLIP_COMPANY_ID=${PAPERCLIP_COMPANY_ID:-6da87f11-6a27-4627-b101-924d5a161f6e}
ENVFILE

# GitHub CLI auth (uses GITHUB_TOKEN env var automatically)
if [ -n "${GITHUB_TOKEN}" ]; then
  echo "${GITHUB_TOKEN}" | gh auth login --with-token 2>/dev/null && echo "[hermes-gateway] gh CLI authenticated." || echo "[hermes-gateway] gh auth failed (non-blocking)."
fi

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
