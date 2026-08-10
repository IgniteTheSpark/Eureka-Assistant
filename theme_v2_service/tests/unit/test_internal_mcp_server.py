from app.internal_mcp import server
from app.internal_mcp.server import mcp
from app.internal_mcp.tools import TOOL_HANDLERS


async def test_stdio_server_freezes_legacy_surface_and_hides_trusted_context():
    tools = await mcp.get_tools()

    assert set(tools) == set(TOOL_HANDLERS)
    for tool in tools.values():
        properties = tool.parameters["properties"]
        assert "user_id" not in properties
        assert "session_id" not in properties
        assert "source_input_turn_id" not in properties
        assert "tool_call_id" not in properties
        assert tool.description
        assert tool.output_schema["x-fastmcp-wrap-result"] is True
        assert tool.output_schema["properties"]["result"] == {"type": "string"}

    assert tools["tool_create_asset"].parameters["properties"]["payload"] == {
        "type": "string"
    }
    assert tools["tool_update_asset"].parameters["properties"][
        "payload_patch"
    ] == {"type": "string"}
    assert tools["tool_update_event"].parameters["properties"]["patch"] == {
        "type": "string"
    }


async def test_todo_tool_accepts_trusted_capture_reference_datetime(monkeypatch):
    captured = {}

    async def fake_execute_tool(name, arguments, *, context, tool_call_id=None):
        captured.update(
            name=name,
            arguments=arguments,
            context=context,
            tool_call_id=tool_call_id,
        )
        return {"ok": True, "asset_id": "todo-1"}

    monkeypatch.setattr(server, "execute_tool", fake_execute_tool)
    todo = (await mcp.get_tools())["tool_create_todo"]

    await todo.run(
        {
            "content": "提醒我吃药",
            "due_date": "2026-08-11T21:00:00+08:00",
            "period": "晚上",
            "occurred_at": "2026-08-11T21:00:00+08:00",
            "reference_datetime": "2026-08-10T16:26:39+08:00",
            "timezone_name": "Asia/Shanghai",
            "user_id": "owner",
            "session_id": "session-1",
            "source_input_turn_id": "turn-1",
            "tool_call_id": "call-1",
        }
    )

    assert captured["name"] == "tool_create_todo"
    assert "reference_datetime" not in captured["arguments"]
    assert captured["context"].reference_datetime.isoformat() == (
        "2026-08-10T16:26:39+08:00"
    )
    assert captured["context"].timezone_name == "Asia/Shanghai"


async def test_target_resolver_accepts_hidden_session_provenance(monkeypatch):
    captured = {}

    async def fake_execute_tool(name, arguments, *, context, tool_call_id=None):
        captured.update(name=name, arguments=arguments, context=context)
        return {"ok": True, "status": "not_found"}

    monkeypatch.setattr(server, "execute_tool", fake_execute_tool)
    resolver = (await mcp.get_tools())["tool_resolve_capture_target"]

    await resolver.run(
        {
            "entity_type": "expense",
            "source_text": "把刚刚那个账单改成 8 元",
            "user_id": "owner",
            "session_id": "session-1",
            "source_input_turn_id": "turn-2",
        }
    )

    assert captured["name"] == "tool_resolve_capture_target"
    assert captured["context"].session_id == "session-1"
    assert captured["context"].input_turn_id == "turn-2"
