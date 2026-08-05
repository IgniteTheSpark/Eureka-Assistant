from app.db.models import UserSkill
from app.domains.sessions.models import ChatSession, InputTurn
from app.domains.sessions.tools import SessionToolExecutor


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
    executor = SessionToolExecutor(
        user_id="owner", session_id=chat.id, input_turn_id=turn.id
    )

    created = await executor.execute(
        "create_asset",
        {
            "skill_machine_name": "running",
            "payload": {"distance": 5, "acceptance_marker": "agent-only"},
        },
    )
    assert created.response["ok"] is True
    assert created.response["payload"] == {
        "distance": 5,
        "acceptance_marker": "agent-only",
    }

    foreign = SessionToolExecutor(
        user_id="foreign", session_id=chat.id, input_turn_id="turn-2"
    )
    queried = await foreign.execute("query_assets", {"limit": 20})
    assert queried.response == {"ok": True, "assets": []}
