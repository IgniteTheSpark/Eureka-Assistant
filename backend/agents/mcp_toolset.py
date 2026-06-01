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
import sys

from google.adk.tools.mcp_tool.mcp_toolset import (
    MCPToolset,
    StdioServerParameters,
    StreamableHTTPConnectionParams,
    SseConnectionParams,
)

_toolset: MCPToolset | None = None
_external_toolsets: dict[str, MCPToolset] = {}


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
        _external_toolsets[name] = MCPToolset(connection_params=conn)

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
    """
    from agents.mcp_config import MCP_SERVERS
    return [get_external_toolset(name) for name in MCP_SERVERS]


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
