import asyncio

from sqlalchemy import func, select

from app.db.models import AgentToolExecution, Asset, UserSkill
from app.db.session import AsyncSessionFactory
from app.domains.sessions.models import ChatSession, InputTurn
from app.internal_mcp.tools import EurekaToolContext, execute_tool


async def _seed_high_fanout_turn() -> tuple[str, str]:
    async with AsyncSessionFactory() as database:
        chat = ChatSession(
            user_id="high-fanout-owner",
            session_type="flash",
        )
        skill = UserSkill(
            user_id="high-fanout-owner",
            machine_name="stress_record",
            display_name="压力记录",
            schema_json={
                "type": "object",
                "properties": {"value": {"type": "integer"}},
                "x-capture-enabled": True,
            },
        )
        database.add_all([chat, skill])
        await database.flush()
        turn = InputTurn(
            user_id="high-fanout-owner",
            session_id=chat.id,
            turn_index=0,
            text="一条包含二十项记录的闪念",
            source="hardware",
        )
        database.add(turn)
        await database.commit()
        return chat.id, turn.id


async def test_twenty_sibling_intents_commit_without_gap_lock_deadlocks(session):
    session_id, turn_id = await _seed_high_fanout_turn()

    async def create(index: int):
        return await execute_tool(
            "tool_create_asset",
            {
                "user_skill_name": "stress_record",
                "payload": {"value": index},
            },
            context=EurekaToolContext(
                user_id="high-fanout-owner",
                session_id=session_id,
                input_turn_id=turn_id,
                idempotency_prefix=f"turn:{turn_id}",
                intent_id=f"intent-{index}",
                intent_operation="create",
            ),
            tool_call_id=f"high-fanout-{index}",
        )

    results = await asyncio.gather(*(create(index) for index in range(20)))

    assert [result.get("ok") for result in results] == [True] * 20
    assert len({result["asset_id"] for result in results}) == 20
    async with AsyncSessionFactory() as database:
        assert (
            await database.scalar(select(func.count()).select_from(Asset))
            == 20
        )
        assert (
            await database.scalar(
                select(func.count()).select_from(AgentToolExecution)
            )
            == 20
        )
