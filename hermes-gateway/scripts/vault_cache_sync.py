#!/usr/bin/env python3
"""
Hermes Vault Cache Sync — Flow 1 (GitHub -> Hermes)

Roda dentro do container Hermes como daemon em background. A cada
VAULT_CACHE_INTERVAL_SECONDS (default 300 = 5min):

  1. Pega o SHA do HEAD atual de origin/main via GET /repos/.../commits/main.
  2. Se o SHA mudou desde a última checagem (cache em .last_commit_sha),
     baixa os arquivos de interesse via GitHub Contents API.
  3. Escreve cada arquivo em /root/.hermes/vault_cache/<path>, criando
     subdirs quando necessário.

Arquivos cacheados (glob-like, resolvidos na árvore recursiva):

  - 03_Resources/Kanban/kanban.json          -> status dos projetos
  - 03_Resources/Mission_Control/kanban.json -> fallback path legado
  - MOCs/Visao.md + MOCs/MOC_*.md            -> visão geral e mapas
  - 01_Projects/<projeto>/README.md          -> um por projeto ativo

O objetivo é dar ao Hermes acesso rápido ao "estado curado" do vault sem
clonar o repo inteiro (~150MB). Footprint esperado: <5MB de cache.

Env vars esperadas:
  GITHUB_TOKEN               : PAT com Contents:Read + Metadata:Read
  GITHUB_REPO                : default "JVLegend/SuperJV"
  GITHUB_BRANCH              : default "main"
  HERMES_HOME                : default /root/.hermes
  VAULT_CACHE_INTERVAL_SECONDS : default 300

Silent no-op quando GITHUB_TOKEN não está setado (permite rodar localmente
sem Flow 1 ativo).
"""

from __future__ import annotations

import base64
import fnmatch
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests

# ── Config ────────────────────────────────────────────────────────────────────
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
GITHUB_REPO = os.environ.get("GITHUB_REPO", "JVLegend/SuperJV").strip()
GITHUB_BRANCH = os.environ.get("GITHUB_BRANCH", "main").strip()
HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/root/.hermes"))
CACHE_DIR = HERMES_HOME / "vault_cache"
SHA_FILE = CACHE_DIR / ".last_commit_sha"
LOG_FILE = CACHE_DIR / "daemon.log"
INTERVAL = int(os.environ.get("VAULT_CACHE_INTERVAL_SECONDS", "300"))

API = f"https://api.github.com/repos/{GITHUB_REPO}"
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "hermes-vault-cache-sync",
}

# Patterns a serem cacheados — matched vs. caminhos relativos do repo.
TARGET_PATTERNS = [
    "03_Resources/Kanban/kanban.json",
    "03_Resources/Mission_Control/kanban.json",
    "MOCs/Visao.md",
    "MOCs/MOC_*.md",
    "MOCs/Gamificacao_Vida.md",
    "01_Projects/*/README.md",
    "CLAUDE.md",
]

# Arquivos maiores que isso são ignorados (evita puxar binários acidentalmente).
MAX_FILE_BYTES = 256 * 1024  # 256KB

# ── Logging ───────────────────────────────────────────────────────────────────
CACHE_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("vault-cache-sync")


# ── Helpers ───────────────────────────────────────────────────────────────────
def gh_get(url: str, params: dict[str, Any] | None = None) -> requests.Response:
    """GET com token, raise_for_status, exponential backoff em 429/5xx."""
    for attempt in range(3):
        try:
            r = requests.get(url, headers=HEADERS, params=params, timeout=30)
            if r.status_code == 200:
                return r
            if r.status_code in (403, 429) and "rate limit" in r.text.lower():
                # primário vs secundário — espera conforme reset header.
                reset = int(r.headers.get("X-RateLimit-Reset", "0"))
                wait = max(60, reset - int(time.time())) if reset else 60
                log.warning("rate-limited; sleeping %ds", wait)
                time.sleep(wait)
                continue
            if r.status_code in (500, 502, 503, 504):
                time.sleep(2**attempt)
                continue
            r.raise_for_status()
            return r
        except requests.RequestException as e:
            if attempt == 2:
                raise
            log.warning("request failed (attempt %d): %s", attempt + 1, e)
            time.sleep(2**attempt)
    raise RuntimeError(f"gh_get failed after retries: {url}")


def latest_commit_sha() -> str:
    r = gh_get(f"{API}/commits/{GITHUB_BRANCH}", params={"per_page": 1})
    return r.json()["sha"]


def list_tree(commit_sha: str) -> list[dict[str, Any]]:
    """Lista recursiva da árvore do commit. Um único request."""
    r = gh_get(f"{API}/git/trees/{commit_sha}", params={"recursive": "1"})
    data = r.json()
    if data.get("truncated"):
        log.warning("tree truncated — alguns arquivos podem não ser cacheados")
    return [t for t in data.get("tree", []) if t.get("type") == "blob"]


def matches_any(path: str, patterns: list[str]) -> bool:
    for pat in patterns:
        if fnmatch.fnmatch(path, pat):
            return True
    return False


def fetch_blob(sha: str) -> bytes:
    """Busca blob por SHA (retorna bytes já decodificados)."""
    r = gh_get(f"{API}/git/blobs/{sha}")
    data = r.json()
    if data.get("encoding") == "base64":
        return base64.b64decode(data["content"])
    return data["content"].encode("utf-8")


def write_cache_file(rel_path: str, content: bytes) -> None:
    dest = CACHE_DIR / rel_path
    dest.parent.mkdir(parents=True, exist_ok=True)
    # Write only when changed (idempotente).
    if dest.exists() and dest.read_bytes() == content:
        return
    dest.write_bytes(content)
    log.info("cached %s (%d bytes)", rel_path, len(content))


def sync_once() -> None:
    """Executa uma passada completa. Safe para rodar em loop."""
    if not GITHUB_TOKEN:
        log.info("GITHUB_TOKEN ausente — vault_cache_sync em no-op")
        return

    try:
        head = latest_commit_sha()
    except Exception as e:
        log.error("falha ao buscar HEAD: %s", e)
        return

    last = SHA_FILE.read_text().strip() if SHA_FILE.exists() else ""
    if head == last:
        log.info("no changes (HEAD=%s)", head[:8])
        return

    log.info("HEAD changed: %s -> %s — rebuilding cache", last[:8] or "(none)", head[:8])

    try:
        tree = list_tree(head)
    except Exception as e:
        log.error("falha ao listar tree: %s", e)
        return

    matched = [t for t in tree if matches_any(t["path"], TARGET_PATTERNS)]
    log.info("%d arquivos alvo identificados (de %d no tree)", len(matched), len(tree))

    n_updated = 0
    for item in matched:
        size = item.get("size", 0)
        if size and size > MAX_FILE_BYTES:
            log.warning("skip %s (%d bytes > %d max)", item["path"], size, MAX_FILE_BYTES)
            continue
        try:
            blob = fetch_blob(item["sha"])
        except Exception as e:
            log.error("falha ao baixar %s: %s", item["path"], e)
            continue
        write_cache_file(item["path"], blob)
        n_updated += 1

    # Escreve manifesto pra debug/introspecção rápida do Hermes.
    manifest = {
        "commit": head,
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "files": [{"path": t["path"], "size": t.get("size", 0), "sha": t["sha"]} for t in matched],
    }
    (CACHE_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))

    SHA_FILE.write_text(head)
    log.info("sync done — %d files written, HEAD=%s", n_updated, head[:8])


def main() -> None:
    log.info(
        "vault_cache_sync start repo=%s branch=%s interval=%ds cache=%s",
        GITHUB_REPO,
        GITHUB_BRANCH,
        INTERVAL,
        CACHE_DIR,
    )
    if not GITHUB_TOKEN:
        log.warning("GITHUB_TOKEN vazio — daemon vai ficar ocioso (no-op a cada tick)")

    # Pequeno delay pra não disputar CPU com startup do hermes gateway.
    time.sleep(30)

    while True:
        try:
            sync_once()
        except Exception as e:  # nunca deixar o daemon morrer
            log.exception("erro em sync_once: %s", e)
        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
