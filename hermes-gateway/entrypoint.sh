#!/bin/bash
set -e

HERMES_HOME="${HOME}/.hermes"

# Clean stale config from persistent volume to ensure fresh config every deploy
rm -f "${HERMES_HOME}/config.yaml" "${HERMES_HOME}/.env" "${HERMES_HOME}/SOUL.md"

mkdir -p "${HERMES_HOME}/skills/productivity/jv-superpersona"
mkdir -p "${HERMES_HOME}/skills/productivity/paperclip-bridge"
mkdir -p "${HERMES_HOME}/skills/productivity/doctor-prospector"
mkdir -p "${HERMES_HOME}/skills/productivity/grant-tracker"
mkdir -p "${HERMES_HOME}/skills/productivity/saude-criancas"
mkdir -p "${HERMES_HOME}/skills/productivity/karine-vendas"
mkdir -p "${HERMES_HOME}/skills/productivity/casal-fe"

# Copy all skills from Docker image
for skill_dir in /hermes-skills/*/; do
  skill_name=$(basename "$skill_dir")
  if [ -d "$skill_dir" ]; then
    cp "$skill_dir"* "${HERMES_HOME}/skills/productivity/${skill_name}/" 2>/dev/null
    echo "[hermes-gateway] ${skill_name} skill installed."
  fi
done
chmod +x "${HERMES_HOME}/skills/productivity/paperclip-bridge/pcp.sh" 2>/dev/null

# Detect LLM provider: DGX (primary) → Kimi (secondary) → Gemini (fallback)
if [ -n "${DGX_SECRET_KEY}" ] && [ -n "${DGX_BASE_URL}" ]; then
  export LLM_MODEL="${HERMES_MODEL:-gemma4:27b}"
  export LLM_PROVIDER="custom_openai"
  export LLM_BASE_URL="${DGX_BASE_URL}"
  export LLM_API_KEY="${DGX_SECRET_KEY}"
  export HERMES_MODEL="${LLM_MODEL}"
  export HERMES_PROVIDER="custom_openai"
  export HERMES_INFERENCE_PROVIDER="dgx"
  export OPENAI_API_KEY="${DGX_SECRET_KEY}"
  echo "[hermes-gateway] LLM: DGX/Gemma4 (${LLM_MODEL}) @ ${DGX_BASE_URL}"
elif [ -n "${KIMI_API_KEY}" ]; then
  # HERMES_MODEL=kimi-for-coding triggers _fixed_temperature_for_model=0.6 in
  # auxiliary client paths (flush_memories, title_gen). BUT the main chat loop
  # does NOT set temperature, so Kimi K2.6 still 400s because its server
  # default differs from 0.6. Solution: route through local proxy that
  # forces temperature=0.6 in ALL requests.
  export LLM_MODEL="${HERMES_MODEL:-kimi-for-coding}"
  export KIMI_REAL_URL="https://api.kimi.com"
  export KIMI_PROXY_PORT="18888"
  export KIMI_FORCED_TEMPERATURE="0.6"
  python3 /kimi-proxy.py &
  sleep 1
  # kimi-coding provider respeita KIMI_BASE_URL (auth.py:172)
  export KIMI_BASE_URL="http://127.0.0.1:${KIMI_PROXY_PORT}/coding/v1"
  export LLM_PROVIDER="kimi-coding"
  export LLM_BASE_URL="${KIMI_BASE_URL}"
  export LLM_API_KEY="${KIMI_API_KEY}"
  export HERMES_MODEL="${LLM_MODEL}"
  export HERMES_PROVIDER="kimi-coding"
  export HERMES_INFERENCE_PROVIDER="kimi"
  echo "[hermes-gateway] LLM: Kimi (${LLM_MODEL}) via proxy :${KIMI_PROXY_PORT} (temp forced 0.6)"
elif [ -n "${GOOGLE_API_KEY}" ]; then
  export LLM_MODEL="${HERMES_MODEL:-gemini-2.0-flash}"
  export LLM_PROVIDER="google"
  export LLM_BASE_URL="${GOOGLE_BASE_URL:-https://generativelanguage.googleapis.com/v1beta}"
  export LLM_API_KEY="${GOOGLE_API_KEY}"
  export HERMES_MODEL="${LLM_MODEL}"
  export HERMES_PROVIDER="google"
  export HERMES_INFERENCE_PROVIDER="gemini"
  echo "[hermes-gateway] LLM: Gemini fallback (${LLM_MODEL})"
else
  echo "[hermes-gateway] ERRO: nenhuma API key encontrada (KIMI_API_KEY, GOOGLE_API_KEY ou DGX_SECRET_KEY)"
  exit 1
fi

echo "[hermes-gateway] Writing config..."
cat > "${HERMES_HOME}/config.yaml" << HERMESCONFIG
model:
  default: ${LLM_MODEL}
  provider: ${LLM_PROVIDER}
  base_url: ${LLM_BASE_URL}
  api_key: ${LLM_API_KEY}
  temperature: ${LLM_TEMPERATURE:-0.7}
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

# ── Cron jobs (persistent in volume, seed only if empty) ──────────────────────
# Detect which bot this is: claudinho (família) vs claudiohermes (trabalho)
CRON_DIR="${HERMES_HOME}/cron"
mkdir -p "${CRON_DIR}/output"
SERVICE_NAME="${RAILWAY_SERVICE_NAME:-unknown}"

# Force re-seed if HERMES_FORCE_CRON_RESEED=true (one-time fix for stale crons)
if [ "${HERMES_FORCE_CRON_RESEED}" = "true" ]; then
  rm -f "${CRON_DIR}/jobs.json"
  echo "[hermes-gateway] Force cron reseed requested"
fi
if [ ! -f "${CRON_DIR}/jobs.json" ]; then
  echo "[hermes-gateway] Seeding cron jobs for ${SERVICE_NAME}..."

  if echo "$SERVICE_NAME" | grep -qi "claudinho"; then
    # ── CLAUDINHO (Família JV) ──
    cat > "${CRON_DIR}/jobs.json" << 'CRONJOBS'
[
  {
    "id": "fam-versiculo",
    "name": "Versiculo diario",
    "schedule": "30 9 * * *",
    "prompt": "Bom dia, Karine! Compartilhe um versículo bíblico com uma reflexão curta e carinhosa para começar o dia. Varie os temas: gratidão, família, coragem, provisão, casamento. Tom evangélico batista. Termine com uma oração curta.",
    "skills": ["casal-fe"],
    "enabled": true,
    "created_at": "2026-04-14T18:00:00Z"
  },
  {
    "id": "fam-bomdia",
    "name": "Bom dia familia",
    "schedule": "0 10 * * *",
    "prompt": "Briefing matinal da família Dias: 1) Medicamentos/suplementos do dia (Rebecca: vitamina D, Benjamin: verificar se precisa algo). 2) Dieta Rebecca: o que pode comer hoje (sugerir café da manhã e almoço seguros). 3) Amanda: lembrar de atividade física. 4) ALERTA: Benjamin tem G6PD — dipirona PROIBIDA. Perguntar se alguém tem consulta ou compromisso.",
    "skills": ["saude-criancas"],
    "enabled": true,
    "created_at": "2026-04-14T18:00:00Z"
  },
  {
    "id": "fam-checkin",
    "name": "Check-in saude noturno",
    "schedule": "0 22 * * *",
    "prompt": "Boa noite família! Check-in: Como foi o dia? Amanda se exercitou? Rebecca teve alguma dor de estômago? O que ela comeu? Benjamin está bem? Algum medicamento dado hoje? Lembrar que Alivium é seguro, Novalgina NUNCA. Terminar com versículo de descanso.",
    "skills": ["saude-criancas", "casal-fe"],
    "enabled": true,
    "created_at": "2026-04-14T18:00:00Z"
  },
  {
    "id": "fam-datenight",
    "name": "Date night reminder",
    "schedule": "0 21 * * 4",
    "prompt": "Quinta-feira! Hora de planejar o date night. Sugira um restaurante da lista que ainda não visitaram e uma ideia romântica. Pergunte se querem reservar. Use a skill casal-fe para escolher.",
    "skills": ["casal-fe"],
    "enabled": true,
    "created_at": "2026-04-14T18:00:00Z"
  },
  {
    "id": "fam-leads",
    "name": "Resumo leads semanal",
    "schedule": "0 11 * * 5",
    "prompt": "Sexta! Resumo semanal de vendas para Karine (IA para Médicos): Quantos leads novos esta semana? Quem foi contatado? Follow-ups pendentes? Sugerir 3 ações para a próxima semana. Lembrar dos produtos: Site Premium R$3.500-8K, AEO Doctors R$3.490+/mês, Apps R$8K-58K.",
    "skills": ["karine-vendas"],
    "enabled": true,
    "created_at": "2026-04-14T18:00:00Z"
  }
]
CRONJOBS

  else
    # ── CLAUDIOHERMES (JV AI Labs / Trabalho) ──
    cat > "${CRON_DIR}/jobs.json" << 'CRONJOBS'
[
  {
    "id": "cron-strategy",
    "name": "Estrategia diaria",
    "schedule": "0 11 * * *",
    "prompt": "Leia meu TELOS, Visao.md e kanban.json. Me dê um briefing estratégico: 1 insight sobre alinhamento projetos-visão, 1 risco identificado, 1 sugestão de priorização para hoje. Termine com as 3 ações mais urgentes.",
    "skills": ["jv-superpersona"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  },
  {
    "id": "cron-conteudo",
    "name": "Conteudo diario",
    "schedule": "0 10 * * *",
    "prompt": "Gere conteúdo diário para JV: 1 post LinkedIn (1200-1800 chars, tom profissional IA+medicina), 1 roteiro Reel/Short (30-60s com hook+CTA), 1 legenda Instagram. Use os jargões: Rumo ao topo, Direto ao ponto. Temas: IA Médica, empreendedorismo, liderança cristã.",
    "skills": ["jv-superpersona"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  },
  {
    "id": "cron-grants",
    "name": "Grants report",
    "schedule": "0 10 * * 2,5",
    "prompt": "Relatório de grants: 1) Status dos grants submetidos (AI4PG, PIPE FAPESP, IANAS). 2) Novos editais relevantes para IA+saúde. 3) Alertas de prazo <30 dias. 4) Se algum deadline <7 dias, marcar como URGENTE. Grants ativos: Google.org $3M (17/04), Wellcome £3.5M (22/09), Climate Change AI $150K (15/09), Prêmio Jovem Cientista R$35K (31/07).",
    "skills": ["grant-tracker"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  },
  {
    "id": "cron-produtos",
    "name": "Daily brief produtos",
    "schedule": "15 10 * * *",
    "prompt": "Briefing de produtos: status dos projetos ativos (SmartLab, PacienteAlerta, AEO Doctors, K2A, VagasMedicas). O que avançou ontem? O que está bloqueado? Qual o próximo milestone de cada?",
    "skills": ["jv-superpersona"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  },
  {
    "id": "cron-prospeccao",
    "name": "Doctor prospection",
    "schedule": "0 */3 * * *",
    "prompt": "Prospectar 15 médicos/clínicas sem website em São Paulo via Overpass API. Rotacionar entre: Jardins, Moema, Itaim Bibi, Vila Mariana, Pinheiros, Santana, Tatuapé. Para cada lead sem site, gerar rascunho de cold email oferecendo Site Premium (R$3.500-8.000) e AEO Doctors (R$3.490+/mês). NÃO enviar emails — só gerar rascunhos para minha revisão.",
    "skills": ["doctor-prospector"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  },
  {
    "id": "cron-gene-check",
    "name": "AMR Gene Check",
    "schedule": "0 13 * * 1",
    "prompt": "Status do SmartLab pipeline: quantos dos 12 genes AMR foram processados? (mecA, blaKPC, blaNDM, vanA, mcr-1, blaCTX-M-15 = 6 completos). Quais faltam? Qual o próximo batch? Lembrar: pre-print bioRxiv planejado para Q3 2026.",
    "skills": ["jv-superpersona"],
    "enabled": true,
    "created_at": "2026-04-14T14:00:00Z"
  }
]
CRONJOBS
  fi

  echo "[hermes-gateway] $(cat ${CRON_DIR}/jobs.json | python3 -c 'import sys,json; print(f"{len(json.load(sys.stdin))} cron jobs seeded")')"
else
  echo "[hermes-gateway] Cron jobs already exist ($(cat ${CRON_DIR}/jobs.json | python3 -c 'import sys,json; print(f"{len(json.load(sys.stdin))} jobs")' 2>/dev/null || echo 'file exists'))"
fi

# Write .env for API keys (hermes reads from ~/.hermes/.env)
cat > "${HERMES_HOME}/.env" << ENVFILE
GOOGLE_API_KEY=${GOOGLE_API_KEY}
KIMI_API_KEY=${KIMI_API_KEY}
DGX_SECRET_KEY=${DGX_SECRET_KEY}
DGX_BASE_URL=${DGX_BASE_URL}
OPENAI_API_KEY=${OPENAI_API_KEY:-${DGX_SECRET_KEY}}
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
