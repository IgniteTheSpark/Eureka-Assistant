import json

from app.db.models import Contact, UserSkill
from app.domains.sessions import service as session_service
from app.domains.sessions.models import AgentPendingAction, ChatSession, InputTurn
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
    definitions = await executor.definitions()
    names = [item["function"]["name"] for item in definitions]
    assert names == [
        "tool_create_asset",
        "resolve_pending_contact",
        "cancel_pending_action",
    ]


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


async def test_chat_tool_resolves_only_a_pending_contact_from_its_session(session):
    chat = ChatSession(user_id="owner", session_type="flash")
    other_chat = ChatSession(user_id="owner", session_type="chat")
    session.add_all([chat, other_chat])
    await session.flush()
    turn = InputTurn(
        user_id="owner",
        session_id=chat.id,
        turn_index=0,
        text="Alex 的职业改成设计师",
        source="voice",
    )
    contact = Contact(user_id="owner", name="Alex", company="Acme")
    session.add_all([turn, contact])
    await session.flush()
    pending = AgentPendingAction(
        user_id="owner",
        session_id=chat.id,
        input_turn_id=turn.id,
        kind="contact",
        operation="create_or_update",
        status="pending",
        candidates_json=[
            {"contact_id": contact.id, "name": "Alex", "company": "Acme"}
        ],
        intent_json={"name": "Alex", "patch": {"title": "设计师"}},
    )
    session.add(pending)
    await session.commit()

    context = await session_service.build_chat_context(
        session,
        chat,
        input_turn_id=turn.id,
        timezone_name="Asia/Shanghai",
    )
    pending_context = json.loads(context.records_json)["pending_actions"]
    assert pending_context == [
        {
            "id": pending.id,
            "kind": "contact",
            "operation": "create_or_update",
            "input_turn_id": turn.id,
            "candidates": [
                {"contact_id": contact.id, "name": "Alex", "company": "Acme"}
            ],
            "intent": {"name": "Alex", "patch": {"title": "设计师"}},
        }
    ]
    # End MySQL's repeatable-read snapshot before the independent chat tool
    # transaction resolves the pending action.
    await session.commit()

    wrong_session = SessionToolExecutor(
        user_id="owner",
        session_id=other_chat.id,
        input_turn_id=None,
        runtime=_Runtime(),
    )
    rejected = await wrong_session.execute(
        "resolve_pending_contact",
        {"pending_action_id": pending.id, "contact_id": contact.id},
    )
    assert rejected.response == {
        "ok": False,
        "error": "pending action not found",
    }

    executor = SessionToolExecutor(
        user_id="owner",
        session_id=chat.id,
        input_turn_id=turn.id,
        runtime=_Runtime(),
    )
    resolved = await executor.execute(
        "resolve_pending_contact",
        {"pending_action_id": pending.id, "contact_id": contact.id},
    )

    await session.refresh(contact)
    await session.refresh(pending)
    assert resolved.response["ok"] is True
    assert resolved.response["pending_action"]["status"] == "resolved"
    assert contact.title == "设计师"
    assert pending.resolution_source == "chat"
