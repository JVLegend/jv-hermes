FROM python:3.11-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git curl gpg \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "git+https://github.com/NousResearch/hermes-agent.git@main" python-telegram-bot gcalcli croniter

COPY entrypoint.sh /entrypoint.sh
COPY kimi-proxy.py /kimi-proxy.py
COPY skills/ /hermes-skills/
COPY scripts/vault_sync_summarizer.py /vault_sync_summarizer.py
RUN chmod +x /entrypoint.sh

ENV HOME=/root
EXPOSE 8080

CMD ["/entrypoint.sh"]
