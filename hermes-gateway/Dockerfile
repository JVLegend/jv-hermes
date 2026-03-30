FROM python:3.11-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends git curl \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "git+https://github.com/NousResearch/hermes-agent.git@main"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV HOME=/root
EXPOSE 8080

CMD ["/entrypoint.sh"]
