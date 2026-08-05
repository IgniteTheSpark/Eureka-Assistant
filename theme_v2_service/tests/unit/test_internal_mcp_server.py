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
