import json
from datetime import datetime
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest

from app.internal_mcp.runtime import (
    InternalMCPUnavailable,
    InternalMCPRuntime,
    InternalMCPTrustedContext,
)


class _FakeClient:
    def __init__(self, *, fail_calls: int = 0):
        self.fail_calls = fail_calls
        self.entered = 0
        self.exited = 0
        self.calls: list[tuple[str, dict]] = []

    async def __aenter__(self):
        self.entered += 1
        return self

    async def __aexit__(self, exc_type, exc, traceback):
        self.exited += 1

    async def list_tools(self):
        return [
            SimpleNamespace(
                name="tool_query_asset",
                description="Query assets",
                inputSchema={
                    "type": "object",
                    "properties": {"contains": {"type": "string"}},
                    "additionalProperties": False,
                },
            ),
            SimpleNamespace(
                name="tool_update_asset",
                description="Update an asset",
                inputSchema={
                    "type": "object",
                    "properties": {
                        "asset_id": {"type": "string"},
                        "payload_patch": {"type": "string"},
                    },
                    "required": ["asset_id", "payload_patch"],
                    "additionalProperties": False,
                },
            ),
        ]

    async def call_tool(self, name, arguments, **_):
        self.calls.append((name, dict(arguments)))
        if self.fail_calls:
            self.fail_calls -= 1
            raise RuntimeError("stdio process exited")
        return SimpleNamespace(
            is_error=False,
            content=[
                SimpleNamespace(
                    text=json.dumps(
                        {"ok": True, "tool": name, "arguments": arguments},
                        ensure_ascii=False,
                    )
                )
            ],
            structured_content=None,
        )


def _trusted() -> InternalMCPTrustedContext:
    return InternalMCPTrustedContext(
        user_id="owner",
        session_id="session-1",
        input_turn_id="turn-1",
        tool_call_id="call-1",
        reference_datetime=datetime(
            2026,
            8,
            10,
            16,
            26,
            tzinfo=ZoneInfo("Asia/Shanghai"),
        ),
        timezone_name="Asia/Shanghai",
    )


async def test_runtime_exposes_openai_tools_and_overrides_model_identity():
    fake = _FakeClient()
    runtime = InternalMCPRuntime(
        client_factory=lambda _: fake,
        contract_audit=False,
    )

    definitions = await runtime.list_openai_tools()
    queried = await runtime.call_tool(
        "tool_query_asset",
        {"contains": "跑步", "user_id": "model-selected-owner"},
        trusted=_trusted(),
    )
    updated = await runtime.call_tool(
        "tool_update_asset",
        {
            "asset_id": "asset-1",
            "payload_patch": '{"distance": 6}',
            "session_id": "model-session",
            "source_input_turn_id": "model-turn",
            "tool_call_id": "model-call",
            "user_id": "model-selected-owner",
        },
        trusted=_trusted(),
    )

    assert definitions == [
        {
            "type": "function",
            "function": {
                "name": "tool_query_asset",
                "description": "Query assets",
                "parameters": {
                    "type": "object",
                    "properties": {"contains": {"type": "string"}},
                    "additionalProperties": False,
                },
            },
        },
        {
            "type": "function",
            "function": {
                "name": "tool_update_asset",
                "description": "Update an asset",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "asset_id": {"type": "string"},
                        "payload_patch": {"type": "string"},
                    },
                    "required": ["asset_id", "payload_patch"],
                    "additionalProperties": False,
                },
            },
        },
    ]
    assert fake.calls == [
        (
            "tool_query_asset",
            {"contains": "跑步", "user_id": "owner"},
        ),
        (
            "tool_update_asset",
            {
                "asset_id": "asset-1",
                "payload_patch": '{"distance": 6}',
                "user_id": "owner",
                "session_id": "session-1",
                "source_input_turn_id": "turn-1",
                "tool_call_id": "call-1",
            },
        ),
    ]
    assert queried["ok"] is True
    assert updated["arguments"]["user_id"] == "owner"

    await runtime.close()
    assert fake.entered == 1
    assert fake.exited == 1


async def test_runtime_restarts_once_after_stdio_exit_and_replays_stable_call():
    broken = _FakeClient(fail_calls=1)
    healthy = _FakeClient()
    clients = iter([broken, healthy])
    runtime = InternalMCPRuntime(
        client_factory=lambda _: next(clients),
        contract_audit=False,
    )

    result = await runtime.call_tool(
        "tool_update_asset",
        {"asset_id": "asset-1", "payload_patch": '{"distance": 8}'},
        trusted=_trusted(),
    )

    assert result["ok"] is True
    assert broken.exited == 1
    assert healthy.calls == [
        (
            "tool_update_asset",
            {
                "asset_id": "asset-1",
                "payload_patch": '{"distance": 8}',
                "user_id": "owner",
                "session_id": "session-1",
                "source_input_turn_id": "turn-1",
                "tool_call_id": "call-1",
            },
        )
    ]

    await runtime.close()
    assert healthy.exited == 1


def test_runtime_injects_session_context_into_target_resolution_query():
    arguments = InternalMCPRuntime._trusted_arguments(
        "tool_resolve_capture_target",
        {
            "entity_type": "expense",
            "source_text": "刚刚那个",
            "session_id": "model-session",
            "source_input_turn_id": "model-turn",
        },
        _trusted(),
    )

    assert arguments == {
        "entity_type": "expense",
        "source_text": "刚刚那个",
        "user_id": "owner",
        "session_id": "session-1",
        "source_input_turn_id": "turn-1",
    }


def test_runtime_injects_temporal_context_only_for_declared_tools():
    todo = InternalMCPRuntime._trusted_arguments(
        "tool_create_todo",
        {
            "content": "提醒我吃药",
            "reference_datetime": "model-time",
            "timezone_name": "model-zone",
        },
        _trusted(),
    )
    query = InternalMCPRuntime._trusted_arguments(
        "tool_query_asset",
        {"reference_datetime": "model-time", "timezone_name": "model-zone"},
        _trusted(),
    )

    assert todo["reference_datetime"] == "2026-08-10T16:26:00+08:00"
    assert todo["timezone_name"] == "Asia/Shanghai"
    assert "reference_datetime" not in query
    assert "timezone_name" not in query


async def test_runtime_fails_startup_when_transport_schema_is_incomplete():
    runtime = InternalMCPRuntime(client_factory=lambda _: _FakeClient())

    with pytest.raises(InternalMCPUnavailable, match="failed to start"):
        await runtime.start()

    assert runtime.contract_errors
    assert any("missing from MCP schema" in error for error in runtime.contract_errors)
