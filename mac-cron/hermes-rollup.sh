#!/bin/bash
# Hermes Rollup — weekly consolidation (runs Sundays 23h via launchd).
#
# Trava 3 do design:
#   daily/   files older than 14d  -> merged into weekly/YYYY-Www.md, then deleted
#   weekly/  files older than 90d  -> merged into monthly/YYYY-MM.md,  then deleted
#
# No LLM call in the rollup: just concatenates contents under a dated header.
# Keeps the vault footprint stable (~300KB long-term per Trava 4 estimate).

set -u

VAULT_BASE="${HOME}/Documents/GitHub/SuperJV/03_Resources/Hermes_Sync"
LOG_DIR="${HOME}/Library/Logs/jv-hermes"
LOG_FILE="${LOG_DIR}/rollup.log"
mkdir -p "${LOG_DIR}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

# Portable "older than N days" (macOS find supports -mtime).
rollup_dailies_to_weekly() {
  local bucket="$1"  # trabalho | familia
  local daily_dir="${VAULT_BASE}/${bucket}/daily"
  local weekly_dir="${VAULT_BASE}/${bucket}/weekly"
  mkdir -p "${weekly_dir}"

  local old
  old=$(find "${daily_dir}" -type f -name "*.md" -mtime +14 2>/dev/null)
  [[ -z "${old}" ]] && { log "  [${bucket}] no dailies older than 14d"; return 0; }

  while IFS= read -r daily; do
    [[ -z "${daily}" ]] && continue
    local base
    base=$(basename "${daily}" .md)    # YYYY-MM-DD
    # Derive ISO week using date -j (macOS BSD date).
    local week
    week=$(date -j -f "%Y-%m-%d" "${base}" "+%Y-W%V" 2>/dev/null) || {
      log "  [${bucket}] cannot parse date from ${base}, skipping"
      continue
    }
    local weekly_file="${weekly_dir}/${week}.md"
    if [[ ! -f "${weekly_file}" ]]; then
      echo "# ${week} — Hermes Sync Rollup (${bucket})" > "${weekly_file}"
      echo "" >> "${weekly_file}"
      echo "_Arquivos daily consolidados automaticamente apos 14 dias._" >> "${weekly_file}"
      echo "" >> "${weekly_file}"
    fi
    {
      echo ""
      echo "---"
      echo ""
      echo "## Day: ${base}"
      echo ""
      # Strip the top-level H1 from the daily so we don't have duplicate titles.
      awk 'NR==1 && /^# /{next} {print}' "${daily}"
    } >> "${weekly_file}"
    rm -f "${daily}"
    log "  [${bucket}] rolled ${base} -> ${week}"
  done <<< "${old}"
}

rollup_weeklies_to_monthly() {
  local bucket="$1"
  local weekly_dir="${VAULT_BASE}/${bucket}/weekly"
  local monthly_dir="${VAULT_BASE}/${bucket}/monthly"
  mkdir -p "${monthly_dir}"

  local old
  old=$(find "${weekly_dir}" -type f -name "*.md" -mtime +90 2>/dev/null)
  [[ -z "${old}" ]] && { log "  [${bucket}] no weeklies older than 90d"; return 0; }

  while IFS= read -r weekly; do
    [[ -z "${weekly}" ]] && continue
    local base
    base=$(basename "${weekly}" .md)   # YYYY-Www
    # Best-effort month: parse year from prefix, use current month info from file mtime.
    local stat_fmt
    stat_fmt=$(stat -f "%Sm" -t "%Y-%m" "${weekly}" 2>/dev/null)
    local month="${stat_fmt:-${base:0:7}}"   # fallback
    local monthly_file="${monthly_dir}/${month}.md"
    if [[ ! -f "${monthly_file}" ]]; then
      echo "# ${month} — Hermes Sync Monthly (${bucket})" > "${monthly_file}"
      echo "" >> "${monthly_file}"
      echo "_Semanas consolidadas apos 90 dias._" >> "${monthly_file}"
      echo "" >> "${monthly_file}"
    fi
    {
      echo ""
      echo "---"
      echo ""
      echo "## Week: ${base}"
      echo ""
      awk 'NR==1 && /^# /{next} {print}' "${weekly}"
    } >> "${monthly_file}"
    rm -f "${weekly}"
    log "  [${bucket}] rolled ${base} -> ${month}"
  done <<< "${old}"
}

log "hermes-rollup start"
for bucket in trabalho familia; do
  log "[${bucket}] daily -> weekly"
  rollup_dailies_to_weekly "${bucket}"
  log "[${bucket}] weekly -> monthly"
  rollup_weeklies_to_monthly "${bucket}"
done
log "hermes-rollup done"
