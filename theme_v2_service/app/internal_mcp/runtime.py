"""Lifecycle-managed client for the local Theme V2 Eureka MCP subprocess."""

from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Callable

from fastmcp import Client

from app.internal_mcp.tools import MUTATION_TOOLS


class InternalMCPUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class InternalMCPTrustedContext:
    user_id: str
    session_id: str | None = None
    input_turn_id: str | None = None
    tool_call_id: str | None = None


ClientFactory = Callable[[dict[str, Any]], Any]


def _default_client_factory(config: dict[str, Any]) -> Client:
    return Client(config)


def _client_config() -> dict[str, Any]:
    return {
        "mcpServers": {
            "eureka": {
                "command": sys.executable,
                "args": ["-m", "app.internal_mcp.server"],
                "env": dict(os.environ),
            }
        }
    }


def _tool_schema(tool: Any) -> dict[str, Any]:
    schema = getattr(tool, "inputSchema", None)
    if schema is None:
        schema = getattr(tool, "input_schema", None)
    if not isinstance(schema, dict):
        schema = {"type": "object", "properties": {}}
    return {
        "type": "function",
        "function": {
            "name": str(getattr(tool, "name", "")),
            "description": str(getattr(tool, "description", "") or ""),
            "parameters": schema,
        },
    }


def _result_payload(result: Any) -> dict[str, Any]:
    structured = getattr(result, "structured_content", None)
    if structured is None:
        structured = getattr(result, "structuredContent", None)
    if isinstance(structured, dict):
        wrapped = structured.get("result")
        if isinstance(wrapped, dict):
            return dict(wrapped)
        if isinstance(wrapped, str):
            try:
                parsed = json.loads(wrapped)
            except json.JSONDecodeError:
                parsed = None
            if isinstance(parsed, dict):
                return parsed
        if structured:
            return dict(structured)

    texts: list[str] = []
    for item in getattr(result, "content", None) or []:
        value = getattr(item, "text", None)
        if isinstance(value, str) and value.strip():
            texts.append(value.strip())
            try:
                parsed = json.loads(value)
            except json.JSONDecodeError:
                continue
            if isinstance(parsed, dict):
                return parsed
    return {
        "ok": not bool(getattr(result, "is_error", False)),
        "content": "\n".join(texts),
    }


class InternalMCPRuntime:
    """Own one lazy stdio MCP client and replace it after an unexpected exit."""

    def __init__(self, *, client_factory: ClientFactory = _default_client_factory):
        self._client_factory = client_factory
        self._client: Any | None = None
        self._definitions: list[dict[str, Any]] | None = None
        self._lifecycle_lock = asyncio.Lock()

    async def _start_locked(self) -> None:
        if self._client is not None:
            return
        client = self._client_factory(_client_config())
        try:
            await client.__aenter__()
            tools = await client.list_tools()
        except Exception:
            try:
                await client.__aexit__(None, None, None)
            except Exception:
                pass
            raise
        self._client = client
        self._definitions = [
            definition
            for definition in (_tool_schema(tool) for tool in tools)
            if definition["function"]["name"]
        ]

    async def start(self) -> None:
        async with self._lifecycle_lock:
            try:
                await self._start_locked()
            except Exception as exc:
                raise InternalMCPUnavailable(
                    "internal Eureka MCP failed to start"
                ) from exc

    async def _invalidate(self, failed_client: Any) -> None:
        async with self._lifecycle_lock:
            if self._client is not failed_client:
                return
            self._client = None
            self._definitions = None
            try:
                await failed_client.__aexit__(None, None, None)
            except Exception:
                pass

    async def close(self) -> None:
        async with self._lifecycle_lock:
            client = self._client
            self._client = None
            self._definitions = None
            if client is not None:
                try:
                    await client.__aexit__(None, None, None)
                except Exception:
                    pass

    async def list_openai_tools(self) -> list[dict[str, Any]]:
        await self.start()
        return [dict(item) for item in self._definitions or []]

    @staticmethod
    def _trusted_arguments(
        name: str,
        arguments: dict[str, Any] | None,
        trusted: InternalMCPTrustedContext,
    ) -> dict[str, Any]:
        normalized = dict(arguments or {})
        for key in (
            "user_id",
            "session_id",
            "source_input_turn_id",
            "tool_call_id",
        ):
            normalized.pop(key, None)
        normalized["user_id"] = trusted.user_id
        if name in MUTATION_TOOLS:
            normalized["session_id"] = trusted.session_id or ""
            normalized["source_input_turn_id"] = trusted.input_turn_id or ""
            normalized["tool_call_id"] = trusted.tool_call_id or ""
        return normalized

    async def call_tool(
        self,
        name: str,
        arguments: dict[str, Any] | None,
        *,
        trusted: InternalMCPTrustedContext,
    ) -> dict[str, Any]:
        normalized = self._trusted_arguments(name, arguments, trusted)
        last_error: Exception | None = None
        for attempt in range(2):
            await self.start()
            client = self._client
            assert client is not None
            try:
                result = await client.call_tool(
                    name,
                    normalized,
                    raise_on_error=False,
                )
                return _result_payload(result)
            except Exception as exc:
                last_error = exc
                await self._invalidate(client)
                if attempt:
                    break
        raise InternalMCPUnavailable("internal Eureka MCP call failed") from last_error


@lru_cache
def get_internal_mcp_runtime() -> InternalMCPRuntime:
    return InternalMCPRuntime()
