import json

from app.db.models import UserSkill
from app.domains.sessions.models import ChatSession, InputTurn
from app.domains.sessions.tools import SessionToolExecutor


class _Runtime:
    def __init__(self):
        self.calls = []

    async def list_openai_tools(self):
        return [
            {
                "type": "function",
                "function": {
                    "name": "tool_create_asset",
                    "description": "Create asset",
                    "parameters": {"type": "object", "properties": {}},
                },
            }
        ]

    async def call_tool(self, name, arguments, *, trusted):
        self.calls.append((name, arguments, trusted))
        if name == "tool_query_asset":
            return {"ok": True, "assets": []}
        return {
            "ok": True,
            "asset_id": "asset-1",
            "user_skill_name": arguments["user_skill_name"],
            "payload": json.loads(arguments["payload"]),
        }


class _CardRuntime(_Runtime):
    async def call_tool(self, name, arguments, *, trusted):
        if name == "tool_create_todo":
            return {
                "ok": True,
                "asset_id": "todo-1",
                "user_skill_name": "todo",
                "payload": {"title": "提交评审稿"},
            }
        if name == "tool_create_contact":
            return {
                "ok": True,
                "contact_id": "contact-1",
                "contact_action": "created",
                "name": "冯总",
                "company": "远景",
            }
        if name == "tool_query_contact":
            return {
                "ok": True,
                "contacts": [
                    {"contact_id": "contact-1", "name": "冯总"},
                    {"contact_id": "contact-2", "name": "王总"},
                ],
                "exact_contacts": [
                    {"contact_id": "contact-1", "name": "冯总"}
                ],
            }
        return await super().call_tool(name, arguments, trusted=trusted)


async def test_create_asset_tool_is_owner_scoped_and_agent_writes_are_permissive(session):
    skill = UserSkill(
        user_id="owner",
        machine_name="running",
        display_name="跑步",
        schema_json={
            "type": "object",
            "properties": {"distance": {"type": "number"}},
            "required": ["distance"],
            "additionalProperties": False,
        },
    )
    chat = ChatSession(user_id="owner", session_type="chat")
    session.add_all([skill, chat])
    await session.commit()
    turn = InputTurn(
        user_id="owner",
        session_id=chat.id,
        turn_index=0,
        text="记录跑步五公里",
        source="typed",
    )
    session.add(turn)
    await session.commit()
    runtime = _Runtime()
    executor = SessionToolExecutor(
        user_id="owner",
        session_id=chat.id,
        input_turn_id=turn.id,
        runtime=runtime,
    )

    created = await executor.execute(
        "tool_create_asset",
        {
            "user_skill_name": "running",
            "payload": '{"distance": 5, "acceptance_marker": "agent-only"}',
        },
        tool_call_id="call-create",
    )
    assert created.response["ok"] is True
    assert created.response["payload"] == {
        "distance": 5,
        "acceptance_marker": "agent-only",
    }

    foreign = SessionToolExecutor(
        user_id="foreign",
        session_id=chat.id,
        input_turn_id="turn-2",
        runtime=runtime,
    )
    queried = await foreign.execute("tool_query_asset", {"limit": 20})
    assert queried.response == {"ok": True, "assets": []}
    assert runtime.calls[0][0] == "tool_create_asset"
    assert runtime.calls[0][2].user_id == "owner"
    assert runtime.calls[0][2].tool_call_id == "call-create"
    assert await executor.definitions() == await runtime.list_openai_tools()


async def test_tool_outcomes_include_cards_for_specialized_assets_and_contacts():
    executor = SessionToolExecutor(
        user_id="owner",
        session_id="session-1",
        input_turn_id="turn-1",
        runtime=_CardRuntime(),
    )

    todo = await executor.execute(
        "tool_create_todo",
        {"content": "提交评审稿"},
    )
    contact = await executor.execute(
        "tool_create_contact",
        {"name": "冯总"},
    )
    contacts = await executor.execute(
        "tool_query_contact",
        {"name_query": "冯总"},
    )

    assert todo.cards == [
        {
            "id": "todo-1",
            "asset_id": "todo-1",
            "user_skill_name": "todo",
            "payload": {"title": "提交评审稿"},
        }
    ]
    assert contact.cards == [
        {
            "id": "contact-1",
            "contact_id": "contact-1",
            "card_type": "contact",
            "name": "冯总",
            "company": "远景",
        }
    ]
    assert [item["contact_id"] for item in contacts.cards] == [
        "contact-1",
        "contact-2",
    ]
