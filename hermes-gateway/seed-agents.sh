#!/bin/bash
# seed-agents.sh — Recria as duas orgs e todos os agentes no Paperclip
# Uso: API_URL=https://... API_KEY=pcp_... bash seed-agents.sh
#
# Pré-requisito: Paperclip rodando com Board API Key ativa.

set -e

API="${API_URL:-https://jv-paperclip-production.up.railway.app/api}"
KEY="${API_KEY:-pcp_board_setup_bc5dce235ce5166620bd3d15061636c87fa1be6a3d4298a6}"

_curl() {
  curl -s -H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json" "$@"
}

echo "========================================="
echo " Paperclip Agent Seed Script"
echo " API: ${API}"
echo "========================================="
echo ""

# ─── ORG 1: JV AI Labs ───

echo ">>> Criando Org: JV AI Labs..."
ORG1=$(_curl -X POST "${API}/companies" -d '{"name":"JV AI Labs","slug":"jv-ai-labs"}')
ORG1_ID=$(echo "$ORG1" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERRO'))" 2>/dev/null)

if [ "$ORG1_ID" = "ERRO" ] || [ -z "$ORG1_ID" ]; then
  echo "AVISO: Org pode já existir. Resposta: $ORG1"
  echo "Insira o Company ID manualmente:"
  read -r ORG1_ID
fi
echo "  JV AI Labs ID: ${ORG1_ID}"

create_agent() {
  local company_id="$1"
  local name="$2"
  local role="$3"
  local agents_path="$4"
  local cwd="${5:-/paperclip/vault/SuperJV}"

  echo "  Criando: ${name}..."
  local result=$(_curl -X POST "${API}/companies/${company_id}/agents" -d "{
    \"name\": \"${name}\",
    \"role\": \"${role}\",
    \"status\": \"active\",
    \"adapter\": \"hermes_local\",
    \"adapterConfig\": {
      \"cwd\": \"${cwd}\",
      \"agentsMdPath\": \"${agents_path}\"
    }
  }")
  local agent_id=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','?'))" 2>/dev/null)
  echo "    -> ID: ${agent_id}"
}

echo ""
echo ">>> Criando 11 agentes JV AI Labs..."
create_agent "$ORG1_ID" "CEO"                          "ceo"     "03_Resources/Paperclip/agents/ceo/AGENTS.md"
create_agent "$ORG1_ID" "CTO"                          "cto"     "03_Resources/Paperclip/agents/cto/AGENTS.md"
create_agent "$ORG1_ID" "Agente de Conteúdo"           "general" "03_Resources/Paperclip/agents/marketing/AGENTS.md"
create_agent "$ORG1_ID" "Chief of Staff"               "general" "03_Resources/Paperclip/agents/chief-of-staff/AGENTS.md"
create_agent "$ORG1_ID" "Diretor de Pesquisa & PhD"    "general" "03_Resources/Paperclip/agents/pesquisa/AGENTS.md"
create_agent "$ORG1_ID" "Agente de Crescimento AEO"    "general" "03_Resources/Paperclip/agents/comercial/AGENTS.md"
create_agent "$ORG1_ID" "Analista de Inteligência"     "general" "03_Resources/Paperclip/agents/inteligencia/AGENTS.md"
create_agent "$ORG1_ID" "Agente de Produtividade e Vault" "general" "03_Resources/Paperclip/agents/assistente/AGENTS.md"
create_agent "$ORG1_ID" "Agente de Grants"             "general" "03_Resources/Paperclip/agents/grants/AGENTS.md"
create_agent "$ORG1_ID" "Agente de Produtos"           "general" "03_Resources/Paperclip/agents/produtos/AGENTS.md"
create_agent "$ORG1_ID" "Hermes SRE Monitor"           "general" "03_Resources/Paperclip/agents/sre/AGENTS.md"

# ─── ORG 2: Família JV ───

echo ""
echo ">>> Criando Org: Família JV..."
ORG2=$(_curl -X POST "${API}/companies" -d '{"name":"Família JV","slug":"familia-jv"}')
ORG2_ID=$(echo "$ORG2" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERRO'))" 2>/dev/null)

if [ "$ORG2_ID" = "ERRO" ] || [ -z "$ORG2_ID" ]; then
  echo "AVISO: Org pode já existir. Resposta: $ORG2"
  echo "Insira o Company ID manualmente:"
  read -r ORG2_ID
fi
echo "  Família JV ID: ${ORG2_ID}"

echo ""
echo ">>> Criando 8 agentes Família JV..."
create_agent "$ORG2_ID" "Networking"  "general" ""
create_agent "$ORG2_ID" "Código"      "general" ""
create_agent "$ORG2_ID" "Casal"       "general" ""
create_agent "$ORG2_ID" "Conteúdo"    "general" ""
create_agent "$ORG2_ID" "Pesquisa"    "general" ""
create_agent "$ORG2_ID" "Tendências"  "general" ""
create_agent "$ORG2_ID" "Estratégia"  "general" ""
create_agent "$ORG2_ID" "Saúde"       "general" ""

echo ""
echo "========================================="
echo " SEED COMPLETO!"
echo ""
echo " JV AI Labs:  ${ORG1_ID}"
echo " Família JV:  ${ORG2_ID}"
echo ""
echo " Próximos passos:"
echo "  1. Copie os IDs gerados para SOUL-claudiohermes.md e SOUL-claudinho.md"
echo "  2. Atualize as env vars HERMES_SOUL_CONTENT com base64 dos SOULs"
echo "  3. Redeploy os gateways"
echo "========================================="
