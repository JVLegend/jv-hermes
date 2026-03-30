#!/bin/bash
# set -e  # disabled for debugging

HERMES_HOME="${HOME}/.hermes"
mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"

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

echo "[hermes-gateway] Config written. Contents:"
cat "${HERMES_HOME}/config.yaml"
echo ""
echo "[hermes-gateway] .env contents:"
cat "${HERMES_HOME}/.env"
echo ""
echo "[hermes-gateway] SOUL.md exists: $(test -f ${HERMES_HOME}/SOUL.md && echo yes || echo no)"
echo "[hermes-gateway] Checking hermes installation..."
which hermes
hermes --version 2>&1 || true
pip3 show hermes-agent 2>&1 | head -5 || true

echo "[hermes-gateway] Checking Python module structure..."
python3 -c "
import importlib, pkgutil
# Find hermes-related packages
for pkg in pkgutil.iter_modules():
    if 'hermes' in pkg.name.lower():
        print(f'Found module: {pkg.name}')
" 2>&1 || true

echo "[hermes-gateway] Starting Hermes gateway (verbose)..."
hermes gateway run -v 2>&1 &
GW_PID=$!
echo "[hermes-gateway] Gateway PID: ${GW_PID}"
wait ${GW_PID}
EXIT_CODE=$?
echo "[hermes-gateway] Gateway exited with code ${EXIT_CODE}"
echo "[hermes-gateway] Sleeping to prevent restart loop..."
sleep 300
