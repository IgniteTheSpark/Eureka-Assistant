"""Live-MySQL contract for explicit Message -> InputTurn provenance.

Run inside the backend container:
    python -m scripts.test_unified_asset_provenance
"""

from __future__ import annotations

import asyncio
import uuid

from httpx import ASGITransport, AsyncClient
from sqlalchemy import delete

from core.security import create_token
from core.session_service import (
    create_input_turn_for_message,
    persist_user_message,
)
from db.database import AsyncSessionLocal, async_engine
from db.models import InputTurn, Message, Session, User
from main import app


async def test_user_message_keeps_exact_input_turn() -> None:
    suffix = uuid.uuid4().hex[:12]
    user_id = f"asset-provenance-{suffix}"
    session_id: uuid.UUID | None = None
    turn_id: uuid.UUID | None = None
    message_id: uuid.UUID | None = None

    try:
        async with AsyncSessionLocal() as db:
            user = User(
                id=user_id,
                email=f"{user_id}@example.com",
                password_hash="fixture",
            )
            session = Session(
                user_id=user_id,
                session_type="flash",
                title="来源定位契约",
            )
            db.add_all((user, session))
            await db.commit()
            await db.refresh(session)
            session_id = session.id

            turn = await create_input_turn_for_message(
                db,
                str(session.id),
                user_id,
                "第二条闪念",
                source="voice",
            )
            turn_id = turn.id
            message = await persist_user_message(
                db,
                str(session.id),
                user_id,
                "第二条闪念",
                input_turn_id=str(turn.id),
            )
            message_id = message.id

            assert message.input_turn_id == turn.id

        headers = {"Authorization": f"Bearer {create_token(user_id)}"}
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
            headers=headers,
        ) as client:
            response = await client.get(f"/api/sessions/{session_id}/messages")

        assert response.status_code == 200, response.text
        messages = response.json()["messages"]
        persisted = next(row for row in messages if row["id"] == str(message_id))
        assert persisted["input_turn_id"] == str(turn_id)
    finally:
        async with AsyncSessionLocal() as db:
            if message_id is not None:
                await db.execute(delete(Message).where(Message.id == message_id))
            if turn_id is not None:
                await db.execute(delete(InputTurn).where(InputTurn.id == turn_id))
            if session_id is not None:
                await db.execute(delete(Session).where(Session.id == session_id))
            await db.execute(delete(User).where(User.id == user_id))
            await db.commit()


async def main() -> None:
    try:
        await test_user_message_keeps_exact_input_turn()
        print("PASS - user messages preserve and serialize exact input_turn_id")
    finally:
        await async_engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
