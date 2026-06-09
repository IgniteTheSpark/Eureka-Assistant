"""
Connector catalog for Connected Apps (§1.7.1).

Developer-maintained registry of **which external apps a user can connect** and
**which fields they must fill**. Exposed (without secrets) via `GET /api/connectors`.
The per-user connection + encrypted creds live in the `connected_apps` table, not
here.

Each connector declares:
  - connector_id, name, icon, description
  - auth_type: "gateway_url" (the secret IS a full URL, e.g. 钉钉 AIHub) |
               "token" (a non-secret gateway base URL + a secret bearer token)
  - transport: streamable_http | sse
  - fields:  [{key, label, secret, placeholder}]  — what the connect form renders
  - capability: human text fed to the routing LLM as a hint

`build_connection_params(connector_id, creds)` turns decrypted creds into an ADK
ConnectionParams for the task runner. Beta is gateway/token paste only (no OAuth,
no per-user stdio subprocess — see §1.7.1).
"""
from __future__ import annotations

from typing import Optional

from google.adk.tools.mcp_tool.mcp_toolset import (
    SseConnectionParams,
    StreamableHTTPConnectionParams,
)


# connector_id → spec. `fields[].secret` drives password-masking in the UI and
# the write-only rule in the API.
CONNECTOR_CATALOG: dict[str, dict] = {
    "dingtalk_calendar": {
        "name": "钉钉日历",
        "icon": "📅",
        "auth_type": "gateway_url",
        "transport": "streamable_http",
        "fields": [
            {"key": "url", "label": "AIHub 网关 URL", "secret": True,
             "placeholder": "https://mcp-gw.dingtalk.com/server/<id>?key=<key>"},
        ],
        "capability": "钉钉日历:创建/更新日程事件(create/update calendar event)。",
        "description": "把事件同步到你的钉钉日历。在钉钉 AIHub 实例页「接入信息」复制 Streamable HTTP 网关 URL。",
    },
    "dingtalk_todo": {
        "name": "钉钉待办",
        "icon": "✅",
        "auth_type": "gateway_url",
        "transport": "streamable_http",
        "fields": [
            {"key": "url", "label": "AIHub 网关 URL", "secret": True,
             "placeholder": "https://mcp-gw.dingtalk.com/server/<id>?key=<key>"},
        ],
        "capability": "钉钉待办:创建个人待办(create personal todo)。",
        "description": "把待办同步到钉钉待办。复制对应 AIHub 实例的网关 URL。",
    },
    "dingtalk_notes": {
        "name": "钉钉文档",
        "icon": "📝",
        "auth_type": "gateway_url",
        "transport": "streamable_http",
        "fields": [
            {"key": "url", "label": "AIHub 网关 URL", "secret": True,
             "placeholder": "https://mcp-gw.dingtalk.com/server/<id>?key=<key>"},
        ],
        "capability": "钉钉文档:新建/更新文档(create/update doc)。",
        "description": "把笔记/报告同步成钉钉文档。复制对应 AIHub 实例的网关 URL。",
    },
    # Header-token gateway example: a hosted MCP whose URL is non-secret config
    # and auth is a bearer token. Covers Notion-style hosted MCPs.
    "notion": {
        "name": "Notion",
        "icon": "🗒",
        "auth_type": "token",
        "transport": "streamable_http",
        "fields": [
            {"key": "gateway_url", "label": "MCP 网关 URL", "secret": False,
             "placeholder": "https://<your-notion-mcp-gateway>/mcp"},
            {"key": "token", "label": "访问令牌 (Bearer)", "secret": True,
             "placeholder": "secret_xxx / ntn_xxx"},
        ],
        "capability": "Notion:新建页面、写入内容(create page / append blocks)。",
        "description": "把内容同步到 Notion。需要一个 Notion MCP 网关 URL + 你的集成令牌。",
    },
}

# Auth types we accept on connect.
AUTH_TYPES = {"gateway_url", "token"}


def public_connector(connector_id: str, spec: dict) -> dict:
    """Catalog row for GET /api/connectors — **no secrets**, only field decls."""
    return {
        "connector_id": connector_id,
        "name": spec["name"],
        "icon": spec["icon"],
        "auth_type": spec["auth_type"],
        "fields": spec["fields"],
        "description": spec["description"],
    }


def public_catalog() -> list[dict]:
    return [public_connector(cid, spec) for cid, spec in CONNECTOR_CATALOG.items()]


def get_connector(connector_id: str) -> Optional[dict]:
    return CONNECTOR_CATALOG.get(connector_id)


def validate_credentials(connector_id: str, creds: dict) -> Optional[str]:
    """Return an error message if required fields are missing, else None."""
    spec = CONNECTOR_CATALOG.get(connector_id)
    if not spec:
        return f"unknown connector: {connector_id}"
    if not isinstance(creds, dict):
        return "credentials must be an object"
    for f in spec["fields"]:
        v = creds.get(f["key"])
        if not isinstance(v, str) or not v.strip():
            return f"缺少字段：{f['label']}"
    return None


def build_connection_params(connector_id: str, creds: dict):
    """Decrypted creds → ADK ConnectionParams (streamable_http / sse). Raises
    ValueError on unknown connector or missing/invalid creds."""
    spec = CONNECTOR_CATALOG.get(connector_id)
    if not spec:
        raise ValueError(f"unknown connector: {connector_id}")
    transport = spec.get("transport", "streamable_http")
    auth_type = spec["auth_type"]

    if auth_type == "gateway_url":
        url = (creds.get("url") or "").strip()
        if not url:
            raise ValueError("missing gateway url")
        headers = None
    elif auth_type == "token":
        url = (creds.get("gateway_url") or "").strip()
        token = (creds.get("token") or "").strip()
        if not url or not token:
            raise ValueError("missing gateway_url or token")
        headers = {"Authorization": f"Bearer {token}"}
    else:
        raise ValueError(f"unsupported auth_type: {auth_type}")

    cls = StreamableHTTPConnectionParams if transport == "streamable_http" else SseConnectionParams
    return cls(url=url, headers=headers)
