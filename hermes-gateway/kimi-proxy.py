#!/usr/bin/env python3
"""
Kimi temperature proxy — força temperature=0.6 em todas as requests
para contornar a limitação do modelo kimi-k2.6-code-preview.
Roda em localhost:11434 e encaminha para a API real do Kimi.
"""
import json
import os
import sys
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

KIMI_BASE_URL = os.environ.get("KIMI_REAL_URL", "https://api.kimi.com/coding/v1")
KIMI_API_KEY  = os.environ.get("KIMI_API_KEY", "")
FORCED_TEMP   = float(os.environ.get("KIMI_FORCED_TEMPERATURE", "0.6"))
PROXY_PORT    = int(os.environ.get("KIMI_PROXY_PORT", "18888"))


class KimiProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silencia logs padrão

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body   = self.rfile.read(length)

        # Força temperature=0.6 no body JSON + reescreve nome do modelo
        # para o ID real que a API Kimi reconhece. Também remove sampling
        # params potencialmente conflitantes (top_p etc.) que o modelo
        # kimi-k2.6-code-preview pode rejeitar junto de temperature!=0.6.
        try:
            data = json.loads(body)
            old_temp = data.get("temperature", "<missing>")
            old_model = data.get("model")
            # Reescreve alias hermes-agent → model ID real do Kimi
            if old_model in ("kimi-for-coding", "kimi-k2-5", "kimi-k2.5", "kimi-k2.6"):
                data["model"] = "kimi-k2.6-code-preview"
            data["temperature"] = FORCED_TEMP
            # Remove sampling params que podem conflitar com temperature fixa
            for k in ("top_p", "top_k", "presence_penalty", "frequency_penalty", "best_of", "n"):
                data.pop(k, None)
            sampling = {k: data.get(k) for k in ("temperature","top_p","top_k","n","best_of","presence_penalty","frequency_penalty") if k in data}
            body = json.dumps(data).encode()
            print(f"[kimi-proxy] {self.path} model: {old_model!r} → {data.get('model')!r} temp: {old_temp} → {FORCED_TEMP} sampling={sampling}", flush=True)
            print(f"[kimi-proxy] body head: {body[:300]!r}", flush=True)
        except Exception as e:
            print(f"[kimi-proxy] JSON parse failed: {e}", flush=True)

        # Monta URL real
        target = KIMI_BASE_URL.rstrip("/") + self.path

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {KIMI_API_KEY}",
            "Content-Length": str(len(body)),
        }

        req = urllib.request.Request(target, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(resp_body)
        except urllib.error.HTTPError as e:
            resp_body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(resp_body)

    def do_GET(self):
        target = KIMI_BASE_URL.rstrip("/") + self.path
        headers = {"Authorization": f"Bearer {KIMI_API_KEY}"}
        req = urllib.request.Request(target, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_body = resp.read()
                self.send_response(resp.status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(resp_body)
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.end_headers()


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PROXY_PORT), KimiProxyHandler)
    print(f"[kimi-proxy] Listening on 127.0.0.1:{PROXY_PORT} → {KIMI_BASE_URL} (temp forced to {FORCED_TEMP})", flush=True)
    server.serve_forever()
