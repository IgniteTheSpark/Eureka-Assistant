import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from tests.fakes.auth_helpers import register_user
from app.auth.models import UserAccount
from app.db.models import Contact
from app.db.session import AsyncSessionFactory
from app.domains.sessions.models import (
    AgentPendingAction,
    ChatSession,
    InputTurn,
    SessionMessage,
)
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _seed_pending(client):
    registered = await register_user(client, "pending@example.com")
    token = registered["token"]
    async with AsyncSessionFactory() as database:
        user_id = await database.scalar(
            select(UserAccount.id).where(UserAccount.email == "pending@example.com")
        )
        chat = ChatSession(user_id=user_id, session_type="flash")
        database.add(chat)
        await database.flush()
        turn = InputTurn(
            user_id=user_id,
            session_id=chat.id,
            turn_index=0,
            text="Alex 的职业改成设计师",
            source="voice",
        )
        database.add(turn)
        await database.flush()
        message = SessionMessage(
            user_id=user_id,
            session_id=chat.id,
            input_turn_id=turn.id,
            role="agent",
            status="waiting_confirmation",
            text="请确认要更新哪一位 Alex。",
        )
        acme = Contact(user_id=user_id, name="Alex", company="Acme")
        byte = Contact(user_id=user_id, name="Alex", company="字节")
        database.add_all([message, acme, byte])
        await database.flush()
        pending = AgentPendingAction(
            user_id=user_id,
            session_id=chat.id,
            input_turn_id=turn.id,
            agent_message_id=message.id,
            kind="contact",
            operation="create_or_update",
            status="pending",
            candidates_json=[
                {"contact_id": acme.id, "name": "Alex", "company": "Acme"},
                {"contact_id": byte.id, "name": "Alex", "company": "字节"},
            ],
            intent_json={
                "name": "Alex",
                "patch": {"title": "设计师"},
                "source_text": "Alex 的职业改成设计师",
            },
        )
        database.add(pending)
        await database.flush()
        message.cards_json = [
            {
                "card_type": "pending_contact",
                "pending_action_id": pending.id,
                "candidates": pending.candidates_json,
            }
        ]
        await database.commit()
        return token, pending.id, acme.id, byte.id, message.id


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


async def test_resolve_pending_contact_updates_only_a_stored_candidate(client):
    token, pending_id, acme_id, byte_id, message_id = await _seed_pending(client)

    rejected = await client.post(
        f"/api/agent-pending-actions/{pending_id}/resolve",
        headers=_headers(token),
        json={"contact_id": "not-a-candidate", "resolution_source": "card"},
    )
    assert rejected.status_code == 422

    resolved = await client.post(
        f"/api/agent-pending-actions/{pending_id}/resolve",
        headers=_headers(token),
        json={"contact_id": byte_id, "resolution_source": "card"},
    )
    replay = await client.post(
        f"/api/agent-pending-actions/{pending_id}/resolve",
        headers=_headers(token),
        json={"contact_id": byte_id, "resolution_source": "card"},
    )

    assert resolved.status_code == 200
    assert replay.status_code == 200
    assert resolved.json()["status"] == "resolved"
    async with AsyncSessionFactory() as database:
        acme = await database.get(Contact, acme_id)
        byte = await database.get(Contact, byte_id)
        pending = await database.get(AgentPendingAction, pending_id)
        message = await database.get(SessionMessage, message_id)
    assert acme.title is None
    assert byte.title == "设计师"
    assert pending.selected_entity_id == byte_id
    assert message.status == "done"
    assert message.cards_json[0]["card_type"] == "contact"
    assert message.cards_json[0]["icon"] == "👤"


async def test_cancel_pending_contact_is_idempotent_and_mutates_nothing(client):
    token, pending_id, acme_id, byte_id, message_id = await _seed_pending(client)

    cancelled = await client.post(
        f"/api/agent-pending-actions/{pending_id}/cancel",
        headers=_headers(token),
        json={"resolution_source": "card"},
    )
    replay = await client.post(
        f"/api/agent-pending-actions/{pending_id}/cancel",
        headers=_headers(token),
        json={"resolution_source": "card"},
    )

    assert cancelled.status_code == 200
    assert replay.status_code == 200
    assert cancelled.json()["status"] == "cancelled"
    async with AsyncSessionFactory() as database:
        contacts = [
            await database.get(Contact, acme_id),
            await database.get(Contact, byte_id),
        ]
        message = await database.get(SessionMessage, message_id)
    assert [contact.title for contact in contacts] == [None, None]
    assert message.status == "done"
