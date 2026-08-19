import json
from datetime import date

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from tests.fakes.auth_helpers import register_user
from app.auth.models import UserAccount
from app.db.session import AsyncSessionFactory
from app.domains.capture.models import CaptureRecording
from app.domains.sessions.chat import SessionChatResult, get_session_chat_provider
from app.domains.sessions.legacy_assistant import LegacyChatContext
from app.domains.sessions.models import InputTurn, SessionMessage
from app.domains.sessions import service as session_service
from app.main import app


class _Provider:
    def __init__(self):
        self.calls = []

    async def answer(self, **command):
        self.calls.append(command)
        assert command["question"] == "今天记录了什么？"
        return SessionChatResult(text="你今天有一条随记。")


class _UnexpectedFailureProvider:
    async def answer(self, **command):
        raise RuntimeError("unexpected provider failure")


@pytest_asyncio.fixture
async def client(session):
    provider = _Provider()
    app.dependency_overrides[get_session_chat_provider] = lambda: provider
    app.state.test_session_chat_provider = provider
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://theme-v2.test",
        ) as http_client:
            yield http_client
    finally:
        del app.state.test_session_chat_provider
        app.dependency_overrides.pop(get_session_chat_provider, None)


async def _register(client: AsyncClient) -> str:
    body = await register_user(client, "chat@example.com", password="Secret123!")
    return body["token"]

def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _frames(text: str) -> list[tuple[str, dict]]:
    frames = []
    for raw in text.strip().split("\n\n"):
        lines = raw.splitlines()
        event = next(line[6:].strip() for line in lines if line.startswith("event:"))
        data = next(line[5:].strip() for line in lines if line.startswith("data:"))
        frames.append((event, json.loads(data)))
    return frames


async def test_chat_sse_creates_and_persists_a_durable_turn(client):
    token = await _register(client)
    response = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={"user_text": "今天记录了什么？", "session_id": ""},
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    frames = _frames(response.text)
    assert [event for event, _ in frames] == ["meta", "token", "done"]
    session_id = frames[0][1]["session_id"]
    input_turn_id = frames[0][1]["input_turn_id"]
    assert input_turn_id
    assert frames[1][1]["text"] == "你今天有一条随记。"

    messages = await client.get(
        f"/api/sessions/{session_id}/messages", headers=_headers(token)
    )
    assert [(item["role"], item["status"]) for item in messages.json()["messages"]] == [
        ("user", "done"),
        ("agent", "done"),
    ]
    assert messages.json()["messages"][0]["input_turn_id"] == input_turn_id
    assert messages.json()["messages"][1]["text"] == "你今天有一条随记。"
    async with AsyncSessionFactory() as database:
        turn = await database.get(InputTurn, input_turn_id)
        capture_count = await database.scalar(
            select(func.count()).select_from(CaptureRecording)
        )
    assert turn is not None
    assert turn.session_id == session_id
    assert turn.turn_index == 0
    assert turn.source == "typed"
    assert turn.text == "今天记录了什么？"
    assert turn.provenance_json == {
        "kind": "session_chat",
        "route": "/api/chat",
    }
    assert capture_count == 0
    provider = app.state.test_session_chat_provider
    assert len(provider.calls) == 1
    assert isinstance(provider.calls[0]["context"], LegacyChatContext)
    assert provider.calls[0]["context"].session_id == session_id
    assert provider.calls[0]["context"].input_turn_id == input_turn_id
    assert provider.calls[0]["context"].session_type == "chat"


async def test_chat_persists_all_tool_call_and_result_snapshots(client):
    token = await _register(client)

    class _ToolProvider:
        async def answer(self, **_):
            return SessionChatResult(
                text="两项都改好了。",
                tool_events=[
                    {
                        "event": "tool_call",
                        "data": {
                            "id": "call-1",
                            "name": "tool_update_asset",
                            "arguments": {"asset_id": "asset-1"},
                        },
                    },
                    {
                        "event": "tool_result",
                        "data": {
                            "id": "call-1",
                            "name": "tool_update_asset",
                            "response": {"ok": True, "asset_id": "asset-1"},
                        },
                    },
                    {
                        "event": "tool_call",
                        "data": {
                            "id": "call-2",
                            "name": "tool_update_event",
                            "arguments": {"event_id": "event-1"},
                        },
                    },
                    {
                        "event": "tool_result",
                        "data": {
                            "id": "call-2",
                            "name": "tool_update_event",
                            "response": {"ok": True, "event_id": "event-1"},
                        },
                    },
                ],
            )

    app.dependency_overrides[get_session_chat_provider] = lambda: _ToolProvider()
    response = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={"user_text": "把刚才两项都改一下", "session_id": ""},
    )

    assert response.status_code == 200
    async with AsyncSessionFactory() as database:
        message = await database.scalar(
            select(SessionMessage)
            .where(SessionMessage.role == "agent")
            .order_by(SessionMessage.created_at.desc())
        )
    assert message is not None
    assert [item["id"] for item in message.tool_call_json["calls"]] == [
        "call-1",
        "call-2",
    ]
    assert [item["id"] for item in message.tool_result_json["results"]] == [
        "call-1",
        "call-2",
    ]


async def test_chat_reuses_an_existing_session(client):
    token = await _register(client)
    created = await client.post(
        "/api/sessions",
        headers=_headers(token),
        json={"session_type": "chat"},
    )
    session_id = created.json()["session_id"]
    response = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={"user_text": "今天记录了什么？", "session_id": session_id},
    )
    assert _frames(response.text)[0][1]["session_id"] == session_id

    missing = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={
            "user_text": "今天记录了什么？",
            "session_id": "00000000-0000-0000-0000-000000000000",
        },
    )
    assert missing.status_code == 404


async def test_chat_inside_physical_flash_session_uses_chat_without_new_capture(
    client,
):
    token = await _register(client)
    async with AsyncSessionFactory() as database:
        user_id = await database.scalar(
            select(UserAccount.id).where(UserAccount.email == "chat@example.com")
        )
        assert user_id is not None
        physical = await session_service.get_or_create_daily_flash_session(
            database,
            user_id,
            date(2026, 8, 5),
        )
        session_id = physical.id
        await database.commit()

    response = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={"user_text": "今天记录了什么？", "session_id": session_id},
    )

    assert response.status_code == 200
    meta = _frames(response.text)[0][1]
    assert meta["session_id"] == session_id
    async with AsyncSessionFactory() as database:
        turn = await database.get(InputTurn, meta["input_turn_id"])
        capture_count = await database.scalar(
            select(func.count()).select_from(CaptureRecording)
        )
    assert turn is not None
    assert turn.source == "typed"
    assert turn.session_id == session_id
    assert capture_count == 0


async def test_chat_requires_authentication(client):
    response = await client.post(
        "/api/chat", json={"user_text": "hello", "session_id": ""}
    )
    assert response.status_code == 401


async def test_chat_persists_unexpected_provider_failure_as_terminal(client):
    token = await _register(client)
    app.dependency_overrides[get_session_chat_provider] = (
        lambda: _UnexpectedFailureProvider()
    )

    response = await client.post(
        "/api/chat",
        headers=_headers(token),
        json={"user_text": "今天记录了什么？", "session_id": ""},
    )

    assert response.status_code == 200
    frames = _frames(response.text)
    assert [event for event, _ in frames] == ["meta", "error"]
    assert frames[-1][1]["message"] == "Agent 暂时不可用，请重试"
    assert isinstance(frames[-1][1]["elapsed_ms"], int)
    assert frames[-1][1]["elapsed_ms"] >= 0
    async with AsyncSessionFactory() as database:
        message = await database.scalar(
            select(SessionMessage)
            .where(SessionMessage.role == "agent")
            .order_by(SessionMessage.created_at.desc())
        )
    assert message is not None
    assert message.status == "failed"
    assert message.text == "Agent 暂时不可用，请重试"
    assert message.elapsed_ms == frames[-1][1]["elapsed_ms"]
