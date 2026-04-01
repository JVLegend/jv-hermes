# Hermes Gateway — Guia de Setup e Recuperação

Setup completo para reproduzir os dois bots Telegram + Paperclip em qualquer Railway ou local.

---

## Arquitetura

```
Railway Project: jv-paperclip
├── jv-paperclip          → Paperclip server (Node.js) + hermes_local adapter
│   ├── Dockerfile.railway (raiz do repo)
│   ├── railway-init.sh    → clona vault, configura hermes, inicia server
│   ├── learnings.mjs      → sistema self-improving (PostgreSQL)
│   └── PostgreSQL addon   → banco principal + learnings
│
├── hermes-claudiohermes   → Hermes Gateway → Bot @claudiohermesbot
│   ├── hermes-gateway/Dockerfile
│   ├── hermes-gateway/entrypoint.sh
│   ├── SOUL-claudiohermes.md (base64 → env var)
│   └── Org: JV AI Labs (11 agentes)
│
├── hermes-claudinho       → Hermes Gateway → Bot @claudinhojvbot
│   ├── hermes-gateway/Dockerfile (mesmo)
│   ├── hermes-gateway/entrypoint.sh (mesmo)
│   ├── SOUL-claudinho.md (base64 → env var)
│   └── Org: Família JV (8 agentes)
│
└── Postgres               → PostgreSQL addon (DATABASE_URL auto)
```

---

## Passo 1: Deploy do Paperclip (serviço principal)

### Railway via CLI
```bash
cd /path/to/paperclip
railway link  # selecionar projeto
railway up --service <paperclip-service-id>
```

### Railway via Dashboard
1. Criar novo serviço → Docker → apontar para raiz do repo
2. Build: `Dockerfile.railway`
3. Start: `/app/scripts/railway-init.sh`

### Variáveis de ambiente (jv-paperclip)
```env
# Obrigatórias
DATABASE_URL=<auto do Railway Postgres addon>
BETTER_AUTH_SECRET=<openssl rand -hex 32>
PAPERCLIP_PUBLIC_URL=https://<seu-dominio>.railway.app
SETUP_API_KEY=sk-setup-<gerar qualquer string>

# Vault (clonar SuperJV no container)
GITHUB_TOKEN=<GitHub PAT com acesso ao repo SuperJV>

# Hermes Agent (para hermes_local adapter executar)
KIMI_API_KEY=<chave sk-kimi-...>

# SOUL e SuperPersona (para agents dentro do container)
HERMES_SOUL_CONTENT=<base64 do SOUL.md>
HERMES_SUPERPERSONA_CONTENT=<base64 da skill superpersona>

# Já setados no Dockerfile (defaults OK):
# PORT=3100, SERVE_UI=true, NODE_ENV=production
# PAPERCLIP_DEPLOYMENT_MODE=authenticated
# PAPERCLIP_MIGRATION_AUTO_APPLY=true
```

### Gerar base64 das SOULs
```bash
# No Mac/Linux:
cat hermes-gateway/SOUL-claudiohermes.md | base64 | tr -d '\n'
cat hermes-gateway/SOUL-claudinho.md | base64 | tr -d '\n'
```

---

## Passo 2: Deploy dos Gateways Hermes

Os dois gateways usam o **mesmo Dockerfile e entrypoint**. A diferença está nas env vars (SOUL, bot token, company ID).

### Deploy
```bash
cd hermes-gateway/
railway up --service <claudiohermes-service-id>
railway up --service <claudinho-service-id>
```

### Variáveis — hermes-claudiohermes (@claudiohermesbot)
```env
TELEGRAM_BOT_TOKEN=<token do @claudiohermesbot via BotFather>
KIMI_API_KEY=<chave sk-kimi-...>
HERMES_SOUL_CONTENT=<base64 de SOUL-claudiohermes.md>
HERMES_SUPERPERSONA_CONTENT=<base64 da skill jv-superpersona>
GATEWAY_ALLOW_ALL_USERS=true
PAPERCLIP_API_URL=https://<seu-dominio>.railway.app/api
PAPERCLIP_API_KEY=<Board API Key do Paperclip>
PAPERCLIP_COMPANY_ID=<Company ID da org JV AI Labs>
```

### Variáveis — hermes-claudinho (@claudinhojvbot)
```env
TELEGRAM_BOT_TOKEN=<token do @claudinhojvbot via BotFather>
KIMI_API_KEY=<chave sk-kimi-...>
HERMES_SOUL_CONTENT=<base64 de SOUL-claudinho.md>
HERMES_SUPERPERSONA_CONTENT=<base64 da skill jv-superpersona>
GATEWAY_ALLOW_ALL_USERS=true
PAPERCLIP_API_URL=https://<seu-dominio>.railway.app/api
PAPERCLIP_API_KEY=<Board API Key do Paperclip>
PAPERCLIP_COMPANY_ID=<Company ID da org Família JV>
```

---

## Passo 3: Criar as Orgs e Agentes no Paperclip

Após o Paperclip estar rodando, os agentes precisam ser criados via API.

### Board API Key
Criada automaticamente pelo `railway-init.sh` se `SETUP_API_KEY` estiver setada.

### Criar Org JV AI Labs (11 agentes)
```bash
API=https://<dominio>.railway.app/api
KEY=<board-api-key>

# Criar company
curl -s -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -X POST "$API/companies" \
  -d '{"name":"JV AI Labs","slug":"jv-ai-labs"}'
# Anotar o company ID retornado

# Criar cada agente (repetir para todos 11)
curl -s -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -X POST "$API/companies/<COMPANY_ID>/agents" \
  -d '{
    "name": "CEO",
    "role": "ceo",
    "status": "active",
    "adapter": "hermes_local",
    "adapterConfig": {
      "cwd": "/paperclip/vault/SuperJV",
      "agentsMdPath": "03_Resources/Paperclip/agents/ceo/AGENTS.md"
    }
  }'
```

### Agentes JV AI Labs
| Nome | Role | AGENTS.md path |
|---|---|---|
| CEO | ceo | agents/ceo/AGENTS.md |
| CTO | cto | agents/cto/AGENTS.md |
| Agente de Conteúdo | general | agents/marketing/AGENTS.md |
| Chief of Staff | general | agents/chief-of-staff/AGENTS.md |
| Diretor de Pesquisa & PhD | general | agents/pesquisa/AGENTS.md |
| Agente de Crescimento AEO | general | agents/comercial/AGENTS.md |
| Analista de Inteligência | general | agents/inteligencia/AGENTS.md |
| Agente de Produtividade e Vault | general | agents/assistente/AGENTS.md |
| Agente de Grants | general | agents/grants/AGENTS.md |
| Agente de Produtos | general | agents/produtos/AGENTS.md |
| Hermes SRE Monitor | general | agents/sre/AGENTS.md |

Todos com `cwd: /paperclip/vault/SuperJV` e paths relativos a `03_Resources/Paperclip/`.

### Agentes Família JV (8 agentes)
| Tópico | Role |
|---|---|
| Networking | general |
| Código | general |
| Casal | general |
| Conteúdo | general |
| Pesquisa | general |
| Tendências | general |
| Estratégia | general |
| Saúde | general |

---

## Passo 4: Verificação

```bash
# Health check
curl -s https://<dominio>.railway.app/api/health | python3 -m json.tool

# Listar agentes (via pcp helper)
source hermes-gateway/skills/paperclip-bridge/pcp.sh
pcp health
pcp agents
pcp status

# Testar delegação
pcp wakeup "<agent-id>" "teste de execução"
# Esperar ~2min, depois:
pcp run-log <run-id>

# Testar bots Telegram
# Enviar mensagem no @claudiohermesbot e @claudinhojvbot
```

---

## Setup Local (sem Railway)

### Opção A: Docker Compose
```bash
# Na raiz do repo paperclip:
docker compose -f docker-compose.local.yml up
```

### Opção B: Rodar manualmente
```bash
# 1. Paperclip
export DATABASE_URL="postgresql://user:pass@localhost:5432/paperclip"
export BETTER_AUTH_SECRET="dev-secret"
pnpm install && pnpm build
node server/dist/index.js

# 2. Gateway (em outro terminal)
pip install "git+https://github.com/NousResearch/hermes-agent.git@main" python-telegram-bot
export TELEGRAM_BOT_TOKEN="..."
export KIMI_API_KEY="..."
# Copiar SOUL e config
bash hermes-gateway/entrypoint.sh
```

---

## IDs Atuais (Railway production)

### Railway
- **Project ID**: `e6111248-43ec-4801-aa79-502137cf9acf`
- **jv-paperclip**: `7e5b4249-329b-4a74-8e6f-50e17a4b1445`
- **hermes-claudiohermes**: `684b9b7d-5a00-4666-9821-6888aabd1544`
- **hermes-claudinho**: `1b112022-930a-417b-b82f-8761b6ca357b`
- **Postgres**: `806534b1-1bc5-4375-9d4e-5943d7c3fd5f`

### Paperclip
- **Board API Key**: `pcp_board_setup_bc5dce235ce5166620bd3d15061636c87fa1be6a3d4298a6`
- **JV AI Labs Company ID**: `6da87f11-6a27-4627-b101-924d5a161f6e`
- **Família JV Company ID**: `a254548b-b4e9-4636-ba73-e5e707d95c82`

### Telegram Bots
- **claudiohermes**: @claudiohermesbot (Org JV AI Labs)
- **claudinho**: @claudinhojvbot (Org Família JV, grupo claudinhoabencoado)

---

## Sistema de Learnings

Auto-inicializado pelo `railway-init.sh`. Usa tabela `agent_learnings` no PostgreSQL.

```bash
# Via pcp (remoto, de qualquer lugar)
source hermes-gateway/skills/paperclip-bridge/pcp.sh
pcp learn-log LRN categoria "mensagem"
pcp learn-stats
pcp learn-search "keyword"

# Via SSH no container Paperclip
railway ssh -s jv-paperclip
source /app/scripts/learnings.sh
learn "algo que descobri"
learn-stats
```

---

## Troubleshooting

| Problema | Solução |
|---|---|
| Bot não responde no Telegram | Verificar logs: `railway logs --service <id>`. Verificar TELEGRAM_BOT_TOKEN. |
| 409 Conflict no Telegram | Dois processos no mesmo token. O `--replace` resolve. Aguardar redeploy. |
| Agent `adapter_failed` | Verificar: (1) vault clonado em `/paperclip/vault/SuperJV`, (2) KIMI_API_KEY setada, (3) AGENTS.md path correto |
| Kimi API auth error | Base URL deve ser `api.kimi.com/coding/v1` (NÃO `api.moonshot.ai`). Key começa com `sk-kimi-`. |
| Vault não clonado | Verificar GITHUB_TOKEN no serviço jv-paperclip. Token precisa de acesso ao repo JVLegend/SuperJV. |
| Learnings não funciona | Verificar se `node /app/scripts/learnings.mjs init` rodou (veja logs do startup). |
| python-telegram-bot missing | Já incluído no Dockerfile. Se erro persistir, rebuild a imagem. |

---

*Última atualização: 31/03/2026*
