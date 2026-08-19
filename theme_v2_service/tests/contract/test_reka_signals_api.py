from datetime import datetime
from uuid import uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.db.models import Asset, UserSkill
from tests.fakes.auth_helpers import register_user
from app.main import app


NOW = datetime(2026, 8, 10, 10, 0)


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> tuple[str, str]:
    body = await register_user(client, email, password="Secret123!")
    return body["token"], body["user"]["id"]

def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _todo(session, *, user_id: str) -> str:
    asset_id = str(uuid4())
    skill = await session.scalar(
        select(UserSkill).where(
            UserSkill.user_id == user_id,
            UserSkill.machine_name == "todo",
        )
    )
    assert skill is not None
    session.add(
        Asset(
            id=asset_id,
            user_id=user_id,
            user_skill_id=skill.id,
            payload_json={
                "title": "提交方案",
                "due_date": "2026-08-10T09:00:00Z",
                "status": "pending",
            },
        )
    )
    await session.commit()
    return asset_id


async def test_list_requires_auth_and_returns_stable_signal_contract(
    client,
    session,
    monkeypatch,
):
    unauthorized = await client.get("/api/reka/signals")
    assert unauthorized.status_code == 401
    token, user_id = await _register(client, "owner@example.com")
    asset_id = await _todo(session, user_id=user_id)
    monkeypatch.setattr("app.domains.reka.api.utc_now", lambda: NOW)

    response = await client.get(
        "/api/reka/signals",
        headers=_headers(token),
        params={"timezone": "Asia/Shanghai"},
    )
    repeated = await client.get(
        "/api/reka/signals",
        headers=_headers(token),
        params={"timezone": "Asia/Shanghai"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["ok"] is True
    assert body["partial_failures"] == []
    assert len(body["signals"]) == 1
    signal = body["signals"][0]
    assert signal["kind"] == "overdue"
    assert signal["target"] == {"type": "asset", "id": asset_id}
    assert signal["actions"] == ["open", "snooze", "dismiss"]
    assert repeated.json()["signals"][0]["id"] == signal["id"]


async def test_overdue_snooze_hides_until_timestamp_without_changing_due_at(
    client,
    session,
    monkeypatch,
):
    token, user_id = await _register(client, "snooze@example.com")
    asset_id = await _todo(session, user_id=user_id)
    clock = [NOW]
    monkeypatch.setattr("app.domains.reka.api.utc_now", lambda: clock[0])
    listed = await client.get("/api/reka/signals", headers=_headers(token))
    signal = listed.json()["signals"][0]

    snoozed = await client.post(
        f"/api/reka/signals/{signal['id']}/snooze",
        headers=_headers(token),
        json={"remind_again_at": "2026-08-10T10:15:00Z"},
    )
    hidden = await client.get("/api/reka/signals", headers=_headers(token))
    stored = await session.get(Asset, asset_id)

    assert snoozed.status_code == 200
    assert snoozed.json() == {
        "ok": True,
        "status": "delivered",
        "remind_again_at": "2026-08-10T10:15:00Z",
    }
    assert hidden.json()["signals"] == []
    assert stored is not None
    assert stored.payload_json["due_date"] == "2026-08-10T09:00:00Z"

    clock[0] = datetime(2026, 8, 10, 10, 15)
    resurfaced = await client.get("/api/reka/signals", headers=_headers(token))
    assert resurfaced.json()["signals"][0]["id"] == signal["id"]


async def test_overdue_snooze_rejects_past_timestamp(client, session, monkeypatch):
    token, user_id = await _register(client, "past-snooze@example.com")
    await _todo(session, user_id=user_id)
    monkeypatch.setattr("app.domains.reka.api.utc_now", lambda: NOW)
    listed = await client.get("/api/reka/signals", headers=_headers(token))
    signal_id = listed.json()["signals"][0]["id"]

    response = await client.post(
        f"/api/reka/signals/{signal_id}/snooze",
        headers=_headers(token),
        json={"remind_again_at": "2026-08-10T09:59:59Z"},
    )

    assert response.status_code == 422


async def test_dismiss_is_owner_scoped_and_removes_occurrence(
    client,
    session,
    monkeypatch,
):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    await _todo(session, user_id=owner_id)
    monkeypatch.setattr("app.domains.reka.api.utc_now", lambda: NOW)
    listed = await client.get(
        "/api/reka/signals",
        headers=_headers(owner_token),
    )
    signal_id = listed.json()["signals"][0]["id"]

    cross_user = await client.post(
        f"/api/reka/signals/{signal_id}/dismiss",
        headers=_headers(other_token),
    )
    dismissed = await client.post(
        f"/api/reka/signals/{signal_id}/dismiss",
        headers=_headers(owner_token),
    )
    repeated = await client.post(
        f"/api/reka/signals/{signal_id}/dismiss",
        headers=_headers(owner_token),
    )
    after = await client.get(
        "/api/reka/signals",
        headers=_headers(owner_token),
    )

    assert cross_user.status_code == 404
    assert dismissed.json() == {"ok": True, "status": "dismissed"}
    assert repeated.json() == dismissed.json()
    assert after.json()["signals"] == []


async def test_invalid_timezone_is_rejected(client):
    token, _ = await _register(client, "owner@example.com")

    response = await client.get(
        "/api/reka/signals",
        headers=_headers(token),
        params={"timezone": "Mars/Olympus"},
    )

    assert response.status_code == 422
