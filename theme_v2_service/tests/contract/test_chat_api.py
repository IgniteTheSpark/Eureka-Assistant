import json

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.domains.sessions.chat import SessionChatResult, get_session_chat_provider
from app.main import app


class _Provider:
    async def answer(self, **command):
        assert command["question"] == "今天记录了什么？"
        return SessionChatResult(text="你今天有一条随记。")


@pytest_asyncio.fixture
async def client(session):
    app.dependency_overrides[get_session_chat_provider] = lambda: _Provider()
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://theme-v2.test",
        ) as http_client:
            yield http_client
    finally:
        app.dependency_overrides.pop(get_session_chat_provider, None)


async def _register(client: AsyncClient) -> str:
    response = await client.post(
        "/api/auth/register",
        json={"email": "chat@example.com", "password": "secret1"},
    )
    return response.json()["token"]


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


async def test_chat_requires_authentication(client):
    response = await client.post(
        "/api/chat", json={"user_text": "hello", "session_id": ""}
    )
    assert response.status_code == 401
