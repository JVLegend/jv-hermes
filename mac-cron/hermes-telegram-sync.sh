#!/bin/bash
# Hermes Telegram Sync — Mac side
#
# Every 3h this script pulls the `/root/.hermes/vault_sync/` directory from
# the two Railway services into the corresponding vault daily/ folders:
#
#   hermes-claudiohermes:/root/.hermes/vault_sync/*.md
#     -> 03_Resources/Hermes_Sync/trabalho/daily/*.md
#
#   hermes-claudinho:/root/.hermes/vault_sync/*.md
#     -> 03_Resources/Hermes_Sync/familia/daily/*.md
#
# The LLM summarisation happens on the Railway side (vault_sync_summarizer.py)
# so this script only needs to copy prepared markdown files.
#
# Idempotent: uses `railway ssh` + `cat` to pull individual files and compares
# with `cmp -s` before overwriting, so unchanged files don't update mtime.
#
# Run by launchd plist com.jv.hermes-telegram-sync.

set -u

VAULT_BASE="${HOME}/Documents/GitHub/SuperJV/03_Resources/Hermes_Sync"
JV_HERMES_DIR="${HOME}/Documents/GitHub/jv-hermes"
LOG_DIR="${HOME}/Library/Logs/jv-hermes"
LOG_FILE="${LOG_DIR}/telegram-sync.log"
# Optional notification channel; the file must define TELEGRAM_BOT_TOKEN and
# TELEGRAM_CHAT_ID (both referring to @claudiohermesbot — work channel).
NOTIFY_ENV="${HOME}/.config/jv-hermes/notify.env"

mkdir -p "${LOG_DIR}" "${VAULT_BASE}/trabalho/daily" "${VAULT_BASE}/familia/daily"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Derived from hermes-railway-monitor/notify.sh. Silent no-op when the env
# file is absent so the sync still works on a fresh machine.
notify() {
  local message="$1"
  [[ -f "${NOTIFY_ENV}" ]] || return 0
  # shellcheck disable=SC1090
  source "${NOTIFY_ENV}"
  [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${message}" \
    --max-time 10 > /dev/null 2>&1 || true
}

# Railway CLI needs the project context; cd into jv-hermes (where the project is linked).
cd "${JV_HERMES_DIR}" 2>/dev/null || {
  log "ERROR: cannot cd to ${JV_HERMES_DIR}"
  notify "⚠️ hermes-telegram-sync falhou: cannot cd to ${JV_HERMES_DIR}"
  exit 1
}

command -v railway > /dev/null || {
  log "ERROR: railway CLI not in PATH"
  notify "⚠️ hermes-telegram-sync: railway CLI missing on Mac"
  exit 1
}

# --- core routine ------------------------------------------------------------
sync_service() {
  local service="$1"       # hermes-claudiohermes | hermes-claudinho
  local dest_dir="$2"      # absolute dir in vault

  log "=== ${service} -> ${dest_dir} ==="

  # List available markdown files on the remote (names only).
  local files
  files=$(railway ssh -s "${service}" "ls /root/.hermes/vault_sync/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null" 2>/dev/null)

  if [[ -z "${files}" ]]; then
    log "  (no *.md files on remote)"
    return 0
  fi

  local count=0
  while IFS= read -r fname; do
    [[ -z "${fname}" ]] && continue
    local tmp
    tmp=$(mktemp)
    if railway ssh -s "${service}" "cat /root/.hermes/vault_sync/${fname}" > "${tmp}" 2>/dev/null && [[ -s "${tmp}" ]]; then
      local dest="${dest_dir}/${fname}"
      if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        :  # unchanged
      else
        mv "${tmp}" "${dest}"
        log "  updated ${fname}"
        count=$((count + 1))
        continue
      fi
    fi
    rm -f "${tmp}"
  done <<< "${files}"

  log "  ${count} file(s) updated"
}

log "hermes-telegram-sync start"
sync_service "hermes-claudiohermes" "${VAULT_BASE}/trabalho/daily"
sync_service "hermes-claudinho"     "${VAULT_BASE}/familia/daily"
log "hermes-telegram-sync done"
