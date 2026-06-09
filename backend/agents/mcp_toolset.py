"""
MCPToolset singletons — Phase B v1.4.x.

Two flavors:

1. **Internal toolset** (`get_mcp_toolset`) — connects to our own
   mcp_server/server.py stdio subprocess exposing Eureka CRUD tools
   (create_asset, query_asset, create_event, ...). Shared by Assistant,
   skill_factory, design_agent.

2. **External toolsets** (`get_external_toolset` / `get_all_external_toolsets`)
   — one per third-party MCP listed in agents/mcp_config.MCP_SERVERS
   (Notion, Google Calendar, Dingtalk, ...). Used by task-skill so the model
   can pick the right tool based on user intent.

All toolsets lazy-init on first use; explicit close on app shutdown.
"""
import os
import re
import sys

from google.adk.tools.mcp_tool.mcp_toolset import (
    MCPToolset,
    StdioServerParameters,
    StreamableHTTPConnectionParams,
    SseConnectionParams,
)

_toolset: MCPToolset | None = None
_external_toolsets: dict[str, MCPToolset] = {}

# OpenAI / DeepSeek require every function (tool) name to match this. Some MCP
# servers expose dotted names (e.g. DingTalk calendar's `pat.batch_plan` /
# `pat.batch_grant`) — a single bad name makes the WHOLE tools[] payload 400 on
# DeepSeek. Drop those tools from external toolsets so the rest stay usable.
_VALID_TOOL_NAME = re.compile(r"^[a-zA-Z0-9_-]+$")


def _keep_valid_tool_name(tool, readonly_context=None) -> bool:
    """ADK tool_filter predicate: keep a tool only if its name is LLM-API-legal."""
    return bool(_VALID_TOOL_NAME.match(getattr(tool, "name", "") or ""))


def make_user_id_injector(user_id: str):
    """Return an ADK `before_tool_callback` that forces every tool call to run
    under [user_id].

    The internal tools run in a *shared* MCP subprocess and take `user_id`
    (default "default"). The LLM never provides it, so without this every
    chat/flash-created or -queried record would land under / read from
    "default" — wrong tenant, invisible to the actual user. We override the
    arg after the model emits the call, so the model can't get it wrong.
    """
    def _before_tool(tool, args, tool_context):  # ADK calls (tool, args, tool_context)
        if isinstance(args, dict):
            args["user_id"] = user_id
        return None  # proceed with the (mutated) args

    return _before_tool


def get_mcp_toolset() -> MCPToolset:
    """
    Returns the shared INTERNAL MCPToolset, lazy-initialized on first call.

    Used by:
    - agents/assistant.py (unified Assistant)
    - agents/skill_factory.py (sub-skill agents in Flash Pipeline)
    - agents/design_agent.py
    """
    global _toolset
    if _toolset is None:
        _toolset = MCPToolset(
            connection_params=StdioServerParameters(
                command=sys.executable,
                args=["-m", "mcp_server.server"],
                # Propagate DB / LLM env vars to subprocess
                env=os.environ.copy(),
            )
        )
    return _toolset


def get_external_toolset(name: str) -> MCPToolset:
    """
    Lazy-init + cache one MCPToolset per external MCP listed in
    agents/mcp_config.MCP_SERVERS. Supports three transports:

    - stdio (default):       cfg has `command` + `args` + `env_keys` — we spawn a subprocess
    - streamable_http:       cfg has `url_env` (env var holds full URL with secrets);
                             optional `headers_env` (header name → env var name)
    - sse:                   same shape as streamable_http but uses SseConnectionParams

    Raises ValueError if `name` isn't registered or required env vars missing.
    """
    # Import here to avoid circular import at module load time
    from agents.mcp_config import MCP_SERVERS

    if name in _external_toolsets:
        return _external_toolsets[name]

    cfg = MCP_SERVERS.get(name)
    if cfg is None:
        raise ValueError(
            f"unknown external MCP: {name!r}. "
            f"Configured: {list(MCP_SERVERS)}"
        )

    transport = cfg.get("transport", "stdio")

    if transport == "stdio":
        # Subprocess MCP (e.g. npx-based community MCPs, our fake one)
        env = os.environ.copy()
        for k in cfg.get("env_keys", []):
            if k in os.environ:
                env[k] = os.environ[k]
        conn = StdioServerParameters(
            command=cfg["command"],
            args=cfg["args"],
            env=env,
        )
        _external_toolsets[name] = MCPToolset(connection_params=conn)

    elif transport in ("streamable_http", "sse"):
        # Remote MCP gateway (e.g. Dingtalk AIHub at mcp-gw.dingtalk.com).
        # URL with embedded secret lives in env (cfg names the env var).
        url_env = cfg.get("url_env")
        if not url_env:
            raise ValueError(
                f"MCP {name!r} has transport={transport!r} but no 'url_env' set"
            )
        url = os.environ.get(url_env, "").strip()
        if not url:
            raise ValueError(
                f"MCP {name!r} requires env var {url_env!r} to hold the connection URL "
                f"(get it from the AIHub instance page → 接入信息)"
            )

        # Optional headers: cfg.headers_env maps header_name → env_var_name
        headers: dict | None = None
        h_env_map = cfg.get("headers_env") or {}
        if h_env_map:
            headers = {}
            for header_name, env_var in h_env_map.items():
                v = os.environ.get(env_var)
                if v:
                    headers[header_name] = v
            if not headers:
                headers = None

        params_cls = StreamableHTTPConnectionParams if transport == "streamable_http" else SseConnectionParams
        conn = params_cls(url=url, headers=headers)
        _external_toolsets[name] = MCPToolset(connection_params=conn, tool_filter=_keep_valid_tool_name)

    else:
        raise ValueError(
            f"MCP {name!r} has unknown transport={transport!r}. "
            f"Supported: stdio, streamable_http, sse"
        )

    return _external_toolsets[name]


def get_all_external_toolsets() -> list[MCPToolset]:
    """
    Return MCPToolsets for every configured external MCP. task-skill attaches
    all of these to its ephemeral agent so the LLM can pick the right tool.

    DEPRECATED for the per-user model — kept for the legacy/global dev path.
    The task runner now uses `get_user_external_toolsets(user_id)`.
    """
    from agents.mcp_config import MCP_SERVERS
    return [get_external_toolset(name) for name in MCP_SERVERS]


async def get_user_external_toolsets(user_id: str) -> tuple[list[MCPToolset], list[str]]:
    """
    Build the external MCP toolsets for ONE user from their Connected Apps
    (§1.7.1). Reads `connected_apps` (status != disconnected), decrypts each
    credential blob, and constructs an MCPToolset per connection from the
    catalog's transport. Per-user gateway connections are streamable_http/sse
    (no subprocess), so building fresh each call is cheap.

    Returns `(toolsets, capability_hints)` where `capability_hints` are the
    connectors' human capability strings, to tell the routing LLM what the user
    actually has connected. Also stamps `last_used_at`.
    """
    from datetime import datetime, timezone

    from sqlalchemy import select, update

    from agents.connectors import CONNECTOR_CATALOG, build_connection_params
    from core.crypto import decrypt_credentials
    from db.database import AsyncSessionLocal
    from db.models import ConnectedApp

    toolsets: list[MCPToolset] = []
    hints: list[str] = []
    used_ids: list = []
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(
            select(ConnectedApp).where(
                ConnectedApp.user_id == user_id,
                ConnectedApp.status != "disconnected",
            )
        )).scalars().all()
        for ca in rows:
            creds = decrypt_credentials(ca.credentials_enc)
            if not creds:
                continue
            try:
                conn = build_connection_params(ca.connector_id, creds)
            except ValueError:
                continue
            toolsets.append(MCPToolset(connection_params=conn, tool_filter=_keep_valid_tool_name))
            used_ids.append(ca.id)
            spec = CONNECTOR_CATALOG.get(ca.connector_id) or {}
            cap = spec.get("capability")
            if cap:
                hints.append(f"- {ca.display_name or spec.get('name', ca.connector_id)}: {cap}")
        if used_ids:
            await db.execute(
                update(ConnectedApp)
                .where(ConnectedApp.id.in_(used_ids))
                .values(last_used_at=datetime.now(timezone.utc))
            )
            await db.commit()
    return toolsets, hints


async def close_mcp_toolset() -> None:
    """Tear down the singletons (call from app shutdown handler in main.py)."""
    global _toolset
    for tset in [_toolset, *list(_external_toolsets.values())]:
        if tset is None:
            continue
        try:
            if hasattr(tset, "close"):
                result = tset.close()
                if hasattr(result, "__await__"):
                    await result
        except Exception:
            pass
    _toolset = None
    _external_toolsets.clear()
