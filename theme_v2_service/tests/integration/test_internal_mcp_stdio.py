import json

from fastmcp import Client

from app.config import get_settings
from app.db.models import Contact


async def test_internal_mcp_stdio_process_lists_and_calls_owner_scoped_tool(session):
    session.add(Contact(user_id="owner", name="冯总"))
    await session.commit()
    settings = get_settings()
    client = Client(
        {
            "mcpServers": {
                "eureka": {
                    "command": "python",
                    "args": ["-m", "app.internal_mcp.server"],
                    "env": {
                        "DATABASE_URL": settings.database_url,
                        "JWT_SECRET": settings.jwt_secret,
                        "ENV": settings.env,
                    },
                }
            }
        }
    )

    async with client:
        tools = await client.list_tools()
        result = await client.call_tool(
            "tool_query_contact",
            {"name_query": "冯总", "user_id": "owner"},
        )

    assert "tool_query_contact" in {tool.name for tool in tools}
    assert result.is_error is False
    payload = json.loads(result.content[0].text)
    assert payload["ok"] is True
    assert [item["name"] for item in payload["exact_contacts"]] == ["冯总"]
