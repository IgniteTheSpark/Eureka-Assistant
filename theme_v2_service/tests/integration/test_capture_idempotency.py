import asyncio
from dataclasses import replace

from sqlalchemy import func, select

from app.db.models import AgentToolExecution, Asset, UserSkill
from app.db.session import AsyncSessionFactory
from app.internal_mcp.tools import EurekaToolContext, execute_tool


async def _context(session, *, intent_id: str) -> EurekaToolContext:
    from app.domains.sessions.models import ChatSession, InputTurn

    chat = ChatSession(user_id="owner", session_type="flash")
    session.add(chat)
    await session.flush()
    turn = InputTurn(
        user_id="owner",
        session_id=chat.id,
        turn_index=0,
        text="早上吃饭8块，晚上买菜20块",
        source="hardware",
    )
    session.add(turn)
    await session.commit()
    return EurekaToolContext(
        user_id="owner",
        session_id=chat.id,
        input_turn_id=turn.id,
        idempotency_prefix=f"turn:{turn.id}",
        intent_id=intent_id,
        intent_operation="create",
    )


async def test_same_atomic_intent_cannot_create_two_root_assets(session):
    context = await _context(session, intent_id="intent-1")
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()

    first = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "expense", "payload": {"amount": 8}},
        context=context,
        tool_call_id="model-call-a",
    )
    second = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "expense", "payload": {"amount": 20}},
        context=context,
        tool_call_id="model-call-b",
    )

    assert first["ok"] is True
    assert second == {
        "ok": False,
        "error": "root mutation already completed for atomic intent",
    }
    async with AsyncSessionFactory() as database:
        assert await database.scalar(select(func.count()).select_from(Asset)) == 1
        roots = list(
            await database.scalars(
                select(AgentToolExecution).where(
                    AgentToolExecution.root_mutation_key.is_not(None)
                )
            )
        )
    assert len(roots) == 1


async def test_sibling_atomic_intents_create_two_root_assets(session):
    first_context = await _context(session, intent_id="intent-1")
    second_context = replace(first_context, intent_id="intent-2")
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()

    first = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "expense", "payload": {"amount": 8}},
        context=first_context,
        tool_call_id="model-call-a",
    )
    second = await execute_tool(
        "tool_create_asset",
        {"user_skill_name": "expense", "payload": {"amount": 20}},
        context=second_context,
        tool_call_id="model-call-b",
    )

    assert first["ok"] is True
    assert second["ok"] is True
    async with AsyncSessionFactory() as database:
        assert await database.scalar(select(func.count()).select_from(Asset)) == 2


async def test_concurrent_sibling_tool_calls_for_same_intent_commit_one_root(session):
    context = await _context(session, intent_id="intent-1")
    async with AsyncSessionFactory() as database:
        database.add(
            UserSkill(
                user_id="owner",
                machine_name="expense",
                display_name="消费",
                schema_json={"type": "object", "properties": {}},
            )
        )
        await database.commit()

    results = await asyncio.gather(
        execute_tool(
            "tool_create_asset",
            {"user_skill_name": "expense", "payload": {"amount": 8}},
            context=context,
            tool_call_id="parallel-a",
        ),
        execute_tool(
            "tool_create_asset",
            {"user_skill_name": "expense", "payload": {"amount": 20}},
            context=context,
            tool_call_id="parallel-b",
        ),
    )

    assert sum(result.get("ok") is True for result in results) == 1
    assert {
        result.get("error") for result in results if result.get("ok") is not True
    } == {"root mutation already completed for atomic intent"}
    async with AsyncSessionFactory() as database:
        assert await database.scalar(select(func.count()).select_from(Asset)) == 1
