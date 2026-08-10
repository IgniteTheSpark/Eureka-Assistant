from copy import deepcopy

import pytest
from fastapi import HTTPException

from app import main
from app.internal_mcp import server
from app.internal_mcp.contracts import (
    audit_internal_mcp_contracts,
    trusted_arguments_for_tool,
)
from app.internal_mcp.server import mcp
from app.internal_mcp.tools import MUTATION_TOOLS


async def _definitions():
    tools = await mcp.get_tools()
    return [
        {
            "type": "function",
            "function": {
                "name": name,
                "description": tool.description,
                "parameters": deepcopy(tool.parameters),
            },
        }
        for name, tool in tools.items()
    ]


async def test_all_fastmcp_tools_conform_to_signature_and_trusted_args():
    assert audit_internal_mcp_contracts(await _definitions()) == []


async def test_contract_audit_detects_hidden_arg_signature_drift():
    definitions = await _definitions()
    todo = next(
        item
        for item in definitions
        if item["function"]["name"] == "tool_create_todo"
    )
    todo["function"]["parameters"]["properties"]["reference_datetime"] = {
        "type": "string"
    }

    errors = audit_internal_mcp_contracts(definitions)

    assert any(
        "tool_create_todo" in error
        and "trusted argument reference_datetime is model-visible" in error
        for error in errors
    )


async def test_contract_audit_detects_missing_visible_required_argument():
    definitions = await _definitions()
    update = next(
        item
        for item in definitions
        if item["function"]["name"] == "tool_update_asset"
    )
    update["function"]["parameters"]["required"].remove("payload_patch")

    errors = audit_internal_mcp_contracts(definitions)

    assert any(
        "tool_update_asset required schema arguments drift" in error
        for error in errors
    )


async def test_readiness_reports_internal_mcp_contract_errors(monkeypatch):
    class Settings:
        chat_agent_enabled = True
        capture_agent_enabled = False

        @staticmethod
        def runtime_readiness_errors():
            return []

    class Runtime:
        contract_errors = ("tool_create_todo trusted argument drift",)

    monkeypatch.setattr(main, "get_settings", lambda: Settings())
    monkeypatch.setattr(main, "get_internal_mcp_runtime", lambda: Runtime())

    with pytest.raises(HTTPException) as captured:
        await main.ready()

    assert captured.value.status_code == 503
    assert captured.value.detail == [
        "tool_create_todo trusted argument drift"
    ]


async def test_every_registered_tool_accepts_a_synthetic_transport_call(monkeypatch):
    called = []

    async def fake_execute_tool(name, arguments, *, context, tool_call_id=None):
        called.append(name)
        return {"ok": True}

    monkeypatch.setattr(server, "execute_tool", fake_execute_tool)
    tools = await mcp.get_tools()
    for name, tool in tools.items():
        arguments = {}
        required = set(tool.parameters.get("required") or [])
        for field_name in required:
            schema = tool.parameters["properties"][field_name]
            field_type = schema.get("type")
            arguments[field_name] = {
                "string": "test",
                "integer": 1,
                "number": 1,
                "boolean": True,
                "object": {},
                "array": [],
            }.get(field_type, "test")
        trusted = trusted_arguments_for_tool(
            name,
            is_mutation=name in MUTATION_TOOLS,
        )
        trusted_values = {
            "user_id": "owner",
            "session_id": "session-1",
            "source_input_turn_id": "turn-1",
            "tool_call_id": f"synthetic:{name}",
            "reference_datetime": "2026-08-10T16:26:00+08:00",
            "timezone_name": "Asia/Shanghai",
            "intent_id": "intent-1",
            "intent_operation": "create",
        }
        arguments.update(
            {key: trusted_values[key] for key in trusted}
        )
        await tool.run(arguments)

    assert set(called) == set(tools)
