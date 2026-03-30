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
echo "[hermes-gateway] Starting Hermes gateway (verbose)..."
python3 -c "
import sys
sys.path.insert(0, '/usr/local/lib/python3.11/site-packages')
try:
    from hermes_agent.gateway.run import main as gateway_main
    print('[debug] About to call gateway_main()', flush=True)
    gateway_main()
except Exception as e:
    print(f'[debug] Gateway exception: {type(e).__name__}: {e}', flush=True)
    import traceback
    traceback.print_exc()
    sys.exit(1)
" 2>&1
EXIT_CODE=$?
echo "[hermes-gateway] Gateway exited with code ${EXIT_CODE}"
echo "[hermes-gateway] Sleeping to prevent restart loop..."
sleep 300
