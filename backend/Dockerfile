FROM python:3.12-slim AS base

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev gcc curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20 LTS — needed to spawn third-party MCP servers (Google Calendar,
# Dingtalk, Notion, ...) via npx. Each MCP runs as a stdio subprocess
# managed by MCPToolset in agents/mcp_toolset.py.
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

COPY requirements.txt .
# PIP_INDEX_URL: override at build time for China deployments (cross-border
# PyPI crawls at KB/s from mainland ECS — a stalled 30+ min layer in practice).
# deploy/docker-compose.prod.yml passes the Aliyun mirror; local builds default
# to stock PyPI.
ARG PIP_INDEX_URL=https://pypi.org/simple
RUN pip install --no-cache-dir -i ${PIP_INDEX_URL} -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
