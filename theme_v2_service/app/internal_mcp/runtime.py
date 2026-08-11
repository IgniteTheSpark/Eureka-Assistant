"""Lifecycle-managed client for the local Theme V2 Eureka MCP subprocess."""

from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass
from datetime import date, datetime
from functools import lru_cache
from typing import Any, Callable

from fastmcp import Client

from app.internal_mcp.tools import MUTATION_TOOLS
from app.internal_mcp.contracts import (
    ALL_TRUSTED_ARGUMENTS,
    audit_internal_mcp_contracts,
    trusted_arguments_for_tool,
)


class InternalMCPUnavailable(RuntimeError):
    pass


@dataclass(frozen=True)
class InternalMCPTrustedContext:
    user_id: str
    session_id: str | None = None
    input_turn_id: str | None = None
    tool_call_id: str | None = None
    reference_datetime: datetime | None = None
    timezone_name: str = "Asia/Shanghai"
    intent_id: str | None = None
    intent_operation: str | None = None
    source_text: str | None = None
    source_anchor_date: date | None = None
    source_period: str | None = None


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

    def __init__(
        self,
        *,
        client_factory: ClientFactory = _default_client_factory,
        contract_audit: bool = True,
    ):
        self._client_factory = client_factory
        self._contract_audit = contract_audit
        self._client: Any | None = None
        self._definitions: list[dict[str, Any]] | None = None
        self._contract_errors: tuple[str, ...] = ()
        self._lifecycle_lock = asyncio.Lock()

    @property
    def contract_errors(self) -> tuple[str, ...]:
        return self._contract_errors

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
        definitions = [
            definition
            for definition in (_tool_schema(tool) for tool in tools)
            if definition["function"]["name"]
        ]
        errors = (
            audit_internal_mcp_contracts(definitions)
            if self._contract_audit
            else []
        )
        self._contract_errors = tuple(errors)
        if errors:
            await client.__aexit__(None, None, None)
            raise RuntimeError("internal MCP contract audit failed")
        self._client = client
        self._definitions = definitions

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
        for key in ALL_TRUSTED_ARGUMENTS:
            normalized.pop(key, None)
        declared = trusted_arguments_for_tool(
            name,
            is_mutation=name in MUTATION_TOOLS,
        )
        values = {
            "user_id": trusted.user_id,
            "session_id": trusted.session_id or "",
            "source_input_turn_id": trusted.input_turn_id or "",
            "tool_call_id": trusted.tool_call_id or "",
            "reference_datetime": (
                trusted.reference_datetime.isoformat()
                if trusted.reference_datetime is not None
                else ""
            ),
            "timezone_name": trusted.timezone_name,
            "intent_id": trusted.intent_id or "",
            "intent_operation": trusted.intent_operation or "",
            "source_text": trusted.source_text or "",
            "source_anchor_date": (
                trusted.source_anchor_date.isoformat()
                if trusted.source_anchor_date is not None
                else ""
            ),
            "source_period": trusted.source_period or "",
        }
        for key in declared:
            if key in {"intent_id", "intent_operation"} and not values[key]:
                continue
            normalized[key] = values[key]
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
