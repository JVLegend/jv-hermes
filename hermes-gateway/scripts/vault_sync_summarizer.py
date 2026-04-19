#!/usr/bin/env python3
"""
Vault Sync Summarizer — Hermes side.

Runs as a background daemon inside the Railway container. Every 3 hours,
reads the chat sessions from `$HERMES_HOME/sessions/` modified in the last
~3 hours, calls the local Kimi proxy to extract substantive content, and
appends the summary to `$HERMES_HOME/vault_sync/YYYY-MM-DD.md`.

The Mac-side launchd job rsync's this directory into the vault.

Hard limits (per Trava 1+2 design):
- LLM is instructed to output up to 10 bullets, skip small-talk.
- Response truncated at 3000 chars.
- If LLM returns "SKIP" (nothing substantive), the run is silent.

Env vars required:
- HERMES_HOME (default: /root/.hermes)
- KIMI_BASE_URL  (already set by entrypoint)
- KIMI_API_KEY   (already set)
- LLM_MODEL      (already set; e.g. kimi-for-coding)
- HERMES_BOT_NAME  (claudiohermes or claudinho; used to pick prompt flavor)
- VAULT_SYNC_INTERVAL_SECONDS  (default 10800 = 3h)
"""

from __future__ import annotations

import json
import os
import sys
import time
import traceback
from datetime import datetime
from pathlib import Path

import requests

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/root/.hermes"))
SESSIONS_DIR = HERMES_HOME / "sessions"
OUTPUT_DIR = HERMES_HOME / "vault_sync"

INTERVAL = int(os.environ.get("VAULT_SYNC_INTERVAL_SECONDS", str(3 * 3600)))
# Slight overlap on the window so we don't miss sessions right at the edge.
WINDOW_SECONDS = INTERVAL + 600

MAX_CHARS_OUTPUT = 3000
MAX_LLM_INPUT_CHARS = 40000  # truncate input if massive

BOT_NAME = os.environ.get("HERMES_BOT_NAME", "bot")
PROMPT_FLAVOR_TRABALHO = """Voce eh um resumidor de logs do bot Telegram @claudiohermesbot (JV AI Labs).
Os participantes sao JV (engenheiro/CEO) e o bot Hermes.

Leia as conversas abaixo e extraia SOMENTE itens substantivos:
- Decisoes tomadas por JV ("aprovado", "vamos", "delegado")
- Prazos/datas mencionadas (e para o que sao)
- Leads/contatos novos (nomes, empresas, clinicas)
- Outputs de crons com informacao relevante (estrategia, conteudo, grants, produtos)
- Insights estrategicos / novos projetos

IGNORE: cumprimentos, small-talk, "ok", "certo", pergunta/resposta casual,
checagens de status sem acao, tentativas de teste."""

PROMPT_FLAVOR_FAMILIA = """Voce eh um resumidor de logs do bot Telegram @claudinhojvbot (Familia Dias).
Os participantes sao JV, Karine (esposa), e o bot Claudinho. Identifique quem falou
quando houver pistas no conteudo.

Leia as conversas abaixo e extraia SOMENTE itens substantivos:
- Saude das criancas (Amanda/Rebecca/Benjamin): sintomas, medicamentos, consultas
- Trabalho da Karine: leads, vendas IA para Medicos, follow-ups
- Casal/fe: date nights planejados, oracoes, versiculos relevantes
- Agendamentos, consultas, compromissos
- Decisoes de JV ou Karine

IGNORE: cumprimentos, "ok", "bom dia" isolados, small-talk."""


def log(msg: str) -> None:
    print(f"[vault-sync {datetime.now().isoformat(timespec='seconds')}] {msg}", flush=True)


def collect_recent_sessions(window_seconds: int) -> list[tuple[str, object]]:
    """Return (filename, parsed_content) tuples for sessions modified within window."""
    if not SESSIONS_DIR.exists():
        return []
    cutoff = time.time() - window_seconds
    out: list[tuple[str, object]] = []

    for f in sorted(SESSIONS_DIR.iterdir()):
        if not f.is_file():
            continue
        if f.stat().st_mtime < cutoff:
            continue
        try:
            if f.suffix == ".jsonl":
                msgs = []
                for line in f.read_text().splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        msgs.append(json.loads(line))
                    except Exception:
                        pass
                out.append((f.name, msgs))
            elif f.suffix == ".json":
                data = json.loads(f.read_text())
                out.append((f.name, data))
        except Exception as exc:
            log(f"  skip {f.name}: {exc}")
    return out


def flatten_messages(data) -> list[dict]:
    """Best-effort flatten of Hermes session format into a list of {role, content} dicts."""
    if isinstance(data, list):
        return [m for m in data if isinstance(m, dict)]
    if isinstance(data, dict):
        for key in ("messages", "history", "transcript", "conversation"):
            val = data.get(key)
            if isinstance(val, list):
                return [m for m in val if isinstance(m, dict)]
    return []


def render_sessions_for_llm(sessions: list[tuple[str, object]]) -> str:
    parts: list[str] = []
    for fname, data in sessions:
        msgs = flatten_messages(data)
        if not msgs:
            continue
        parts.append(f"\n=== Session: {fname} ===")
        for m in msgs:
            role = m.get("role", "?")
            content = m.get("content", "")
            if not isinstance(content, str):
                content = json.dumps(content, ensure_ascii=False)[:500]
            content = content.strip()
            if not content:
                continue
            # Skip system/meta roles that bloat input
            if role in ("session_meta", "system", "tool"):
                continue
            parts.append(f"[{role}] {content[:800]}")
        if sum(len(p) for p in parts) > MAX_LLM_INPUT_CHARS:
            parts.append("\n... (truncado por tamanho) ...")
            break
    return "\n".join(parts)


def build_prompt(rendered: str) -> str:
    flavor = PROMPT_FLAVOR_FAMILIA if BOT_NAME == "claudinho" else PROMPT_FLAVOR_TRABALHO
    return f"""{flavor}

Se nao houver NADA substantivo, responda APENAS a palavra SKIP.

Formato de saida: markdown com bullets. Maximo 10 bullets no total.
Nao inclua preambulo, titulo ou conclusao. Apenas os bullets.

=== CONVERSAS (ultimas 3h) ===
{rendered}
=== FIM ==="""


def call_llm(prompt: str) -> str:
    base_url = os.environ["KIMI_BASE_URL"].rstrip("/")
    api_key = os.environ["KIMI_API_KEY"]
    model = os.environ.get("LLM_MODEL", "kimi-for-coding")
    url = f"{base_url}/chat/completions"
    resp = requests.post(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 1200,
        },
        timeout=180,
    )
    resp.raise_for_status()
    payload = resp.json()
    return payload["choices"][0]["message"]["content"].strip()


def append_summary(summary: str) -> Path:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    today = datetime.now().strftime("%Y-%m-%d")
    timestamp = datetime.now().strftime("%H:%M")
    out_file = OUTPUT_DIR / f"{today}.md"

    header_needed = not out_file.exists()
    if len(summary) > MAX_CHARS_OUTPUT:
        summary = summary[:MAX_CHARS_OUTPUT].rstrip() + "\n\n> ...truncado. Ver sessions no Railway."

    with out_file.open("a", encoding="utf-8") as f:
        if header_needed:
            f.write(f"# {today} — Hermes Sync ({BOT_NAME})\n\n")
            f.write("_Resumos automaticos das conversas e crons. Trava: 10 bullets/run, 3000 chars max._\n")
        f.write(f"\n## {timestamp}\n\n{summary}\n")
    return out_file


def run_once() -> None:
    sessions = collect_recent_sessions(WINDOW_SECONDS)
    log(f"found {len(sessions)} recent session files (window={WINDOW_SECONDS}s)")
    if not sessions:
        return
    rendered = render_sessions_for_llm(sessions)
    if not rendered.strip():
        log("rendered empty -> skip")
        return
    log(f"calling LLM ({len(rendered)} chars input)")
    summary = call_llm(build_prompt(rendered))
    if not summary or summary.strip().upper().startswith("SKIP"):
        log("LLM returned SKIP -> no file write")
        return
    out = append_summary(summary)
    log(f"wrote -> {out} ({len(summary)} chars)")


def main() -> None:
    log(f"starting vault sync summarizer for bot={BOT_NAME}, interval={INTERVAL}s")
    # Initial delay so we don't run the second the container starts (let crons settle).
    time.sleep(60)
    while True:
        try:
            run_once()
        except Exception as exc:
            log(f"ERROR: {exc}")
            traceback.print_exc(file=sys.stdout)
            sys.stdout.flush()
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
