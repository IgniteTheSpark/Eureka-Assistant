import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> str:
    response = await client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret1"},
    )
    assert response.status_code == 200
    return response.json()["token"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _asset(client: AsyncClient, token: str) -> str:
    skills = await client.get(
        "/api/user-skills",
        headers=_headers(token),
    )
    skill = next(
        item for item in skills.json() if item["machine_name"] == "notes"
    )
    created = await client.post(
        "/api/assets",
        headers=_headers(token),
        json={
            "user_skill_id": skill["id"],
            "payload": {"title": "上下文", "content": "一条资产"},
        },
    )
    return created.json()["id"]


async def test_session_crud_context_and_owner_scope(client):
    owner = await _register(client, "session-owner@example.com")
    foreign = await _register(client, "session-foreign@example.com")
    asset_id = await _asset(client, owner)

    created = await client.post(
        "/api/sessions",
        headers=_headers(owner),
        json={"session_type": "chat"},
    )
    assert created.status_code == 200
    session_id = created.json()["session_id"]

    listed = await client.get("/api/sessions", headers=_headers(owner))
    assert [item["id"] for item in listed.json()["sessions"]] == [session_id]
    assert listed.json()["sessions"][0]["created_at"].endswith("Z")

    foreign_detail = await client.get(
        f"/api/sessions/{session_id}", headers=_headers(foreign)
    )
    assert foreign_detail.status_code == 404

    source = await client.get(f"/api/assets/{asset_id}", headers=_headers(owner))
    linked = await client.post(
        "/api/assets",
        headers=_headers(owner),
        json={
            "user_skill_id": source.json()["user_skill_id"],
            "payload": {"title": "沉淀", "content": "保留资产"},
            "session_id": session_id,
        },
    )
    assert linked.status_code == 200
    assert linked.json()["session_id"] == session_id

    attached = await client.patch(
        f"/api/sessions/{session_id}/context",
        headers=_headers(owner),
        json={"add": [asset_id]},
    )
    assert attached.status_code == 200
    assert attached.json()["session"]["context_assets"] == [
        {"id": asset_id, "label": "上下文"}
    ]

    detached = await client.patch(
        f"/api/sessions/{session_id}/context",
        headers=_headers(owner),
        json={"remove": [asset_id]},
    )
    assert detached.json()["session"]["context_assets"] == []

    deleted = await client.delete(
        f"/api/sessions/{session_id}", headers=_headers(owner)
    )
    assert deleted.json() == {"ok": True}
    assert (
        await client.get(f"/api/sessions/{session_id}", headers=_headers(owner))
    ).status_code == 404
    surviving_asset = await client.get(
        f"/api/assets/{linked.json()['id']}", headers=_headers(owner)
    )
    assert surviving_asset.status_code == 200
    assert surviving_asset.json()["session_id"] is None


async def test_subject_peek_does_not_create_and_reuses_subject_thread(client):
    owner = await _register(client, "session-subject@example.com")
    peek = await client.post(
        "/api/sessions",
        headers=_headers(owner),
        json={
            "session_type": "chat",
            "subject_type": "asset",
            "subject_id": "asset-1",
            "peek_only": True,
        },
    )
    assert peek.status_code == 200
    assert peek.json()["session_id"] is None
    assert (await client.get("/api/sessions", headers=_headers(owner))).json() == {
        "sessions": []
    }

    created = await client.post(
        "/api/sessions",
        headers=_headers(owner),
        json={
            "session_type": "chat",
            "subject_type": "asset",
            "subject_id": "asset-1",
        },
    )
    reused = await client.post(
        "/api/sessions",
        headers=_headers(owner),
        json={
            "session_type": "chat",
            "subject_type": "asset",
            "subject_id": "asset-1",
            "peek_only": True,
        },
    )
    assert reused.json()["session_id"] == created.json()["session_id"]


async def test_session_routes_require_authentication(client):
    assert (await client.get("/api/sessions")).status_code == 401
    assert (
        await client.post("/api/sessions", json={"session_type": "chat"})
    ).status_code == 401
