"""Contract tests for durable chat mutation receipts.

Run:
    cd backend && python -m scripts.test_chat_mutation_receipt_contract
"""

import asyncio
import time
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

import api.chat as chat_api
from api.chat import build_durable_tool_result
from core.security import create_token
from core.session_service import create_pending_agent_message
from db.database import AsyncSessionLocal, async_engine
from db.models import Base, Message, Session, User
from main import app


def test_successful_delete_receipt_needs_no_card() -> None:
    receipt = build_durable_tool_result([
        {
            "name": "tool_delete_asset",
            "response": {
                "structuredContent": {
                    "result": '{"ok":true,"asset_id":"deleted-asset"}',
                },
            },
        },
    ])

    assert receipt["confirmed_mutation"] is True
    assert receipt["results"][0]["name"] == "tool_delete_asset"


def test_query_and_failed_write_have_no_mutation_receipt() -> None:
    query = build_durable_tool_result([
        {"name": "tool_query_asset", "response": {"ok": True, "assets": []}},
    ])
    failed_write = build_durable_tool_result([
        {"name": "tool_update_asset", "response": {"ok": False, "error": "gone"}},
    ])

    assert query["confirmed_mutation"] is False
    assert failed_write["confirmed_mutation"] is False


async def test_event_only_bulk_turn_persists_and_serializes_receipt() -> None:
    """Exercise bulk runner -> finalizer -> /messages without a render card."""
    suffix = uuid.uuid4().hex[:12]
    user_id = f"receipt-contract-{suffix}"
    session_id = None
    message_id = None
    original_pipeline = chat_api.run_flash_pipeline
    original_bulk_check = chat_api._looks_like_bulk
    original_publish = chat_api.chat_turns.publish
    original_close = chat_api.chat_turns.close
    published = []

    async def fake_pipeline(**_kwargs):
        return {
            "ok": True,
            "summary": "已整理日程",
            "cards": [],
            "derived_assets": [],
            "derived_events": [{"event_id": "event-only"}],
        }

    async def fake_close(*_args, **_kwargs):
        return None

    try:
        async with async_engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        async with AsyncSessionLocal() as db:
            db.add(User(
                id=user_id,
                email=f"{user_id}@example.com",
                password_hash="fixture",
            ))
            session = Session(user_id=user_id, session_type="chat", title="receipt")
            db.add(session)
            await db.commit()
            await db.refresh(session)
            session_id = session.id
            pending = await create_pending_agent_message(db, str(session.id), user_id)
            message_id = pending.id

        chat_api.run_flash_pipeline = fake_pipeline
        chat_api._looks_like_bulk = lambda _text: True
        chat_api.chat_turns.publish = lambda *_args, **_kwargs: published.append(_args)
        chat_api.chat_turns.close = fake_close
        await chat_api._run_chat_turn(
            turn_id=str(message_id),
            user_text="事件批量导入",
            history_text="",
            session_id=str(session_id),
            input_turn_id=str(uuid.uuid4()),
            user_id=user_id,
            event_id="",
            today_str="2026-08-19",
            user_skills_hint="",
            session_assets_hint="",
            session_context_hint="",
            session_subject_hint="",
            t0=time.monotonic(),
        )

        headers = {"Authorization": f"Bearer {create_token(user_id)}"}
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers=headers,
        ) as client:
            response = await client.get(f"/api/sessions/{session_id}/messages")
        assert response.status_code == 200, response.text
        message = next(
            row for row in response.json()["messages"]
            if row["id"] == str(message_id)
        )
        assert message["cards"] == []
        assert message["tool_result"]["confirmed_mutation"] is True
        live_bulk = next(event for event in published if event[1][0] == "tool_result")
        assert live_bulk[1][1]["response"]["confirmed_mutation"] is True
    finally:
        chat_api.run_flash_pipeline = original_pipeline
        chat_api._looks_like_bulk = original_bulk_check
        chat_api.chat_turns.publish = original_publish
        chat_api.chat_turns.close = original_close
        async with AsyncSessionLocal() as db:
            if message_id is not None:
                await db.execute(delete(Message).where(Message.id == message_id))
            if session_id is not None:
                await db.execute(delete(Session).where(Session.id == session_id))
            await db.execute(delete(User).where(User.id == user_id))
            await db.commit()


if __name__ == "__main__":
    async def main() -> None:
        try:
            test_successful_delete_receipt_needs_no_card()
            test_query_and_failed_write_have_no_mutation_receipt()
            await test_event_only_bulk_turn_persists_and_serializes_receipt()
            print("PASS - durable chat mutation receipt contract")
        finally:
            await async_engine.dispose()

    asyncio.run(main())
