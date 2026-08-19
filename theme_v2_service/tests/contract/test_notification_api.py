from datetime import datetime, timedelta

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from tests.fakes.auth_helpers import register_user
from app.main import app


NOW = datetime(2026, 7, 31, 10, 0, 0)


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


async def _create(
    session,
    *,
    user_id: str,
    title: str,
    created_at: datetime,
    read: bool = False,
):
    notification = await create_notification(
        session,
        NotificationCreate(
            user_id=user_id,
            type="report_done",
            title=title,
            body="ready",
            link="/reports/run-1",
        ),
    )
    notification.created_at = created_at
    notification.read = read
    await session.flush()
    return notification


async def test_list_requires_auth_and_returns_owned_notifications(client, session):
    unauthorized = await client.get("/api/notifications")
    assert unauthorized.status_code == 401

    token, user_id = await _register(client, "owner@example.com")
    _, other_user_id = await _register(client, "other@example.com")
    older = await _create(
        session,
        user_id=user_id,
        title="older",
        created_at=NOW - timedelta(minutes=2),
        read=True,
    )
    newer = await _create(
        session,
        user_id=user_id,
        title="newer",
        created_at=NOW - timedelta(minutes=1),
    )
    await _create(
        session,
        user_id=other_user_id,
        title="foreign",
        created_at=NOW,
    )
    await session.commit()

    response = await client.get(
        "/api/notifications",
        headers=_headers(token),
        params={"limit": 30},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["unread"] == 1
    assert [item["id"] for item in body["notifications"]] == [newer.id, older.id]
    assert body["notifications"][0] == {
        "id": newer.id,
        "type": "report_done",
        "title": "newer",
        "body": "ready",
        "link": "/reports/run-1",
        "read": False,
        "created_at": "2026-07-31T09:59:00Z",
    }


async def test_list_validates_limit(client):
    token, _ = await _register(client, "owner@example.com")

    too_small = await client.get(
        "/api/notifications",
        headers=_headers(token),
        params={"limit": 0},
    )
    too_large = await client.get(
        "/api/notifications",
        headers=_headers(token),
        params={"limit": 101},
    )

    assert too_small.status_code == 422
    assert too_large.status_code == 422


async def test_read_is_owner_scoped_and_idempotent(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, other_id = await _register(client, "other@example.com")
    own = await _create(
        session,
        user_id=owner_id,
        title="own",
        created_at=NOW,
    )
    foreign = await _create(
        session,
        user_id=other_id,
        title="foreign",
        created_at=NOW,
    )
    await session.commit()

    cross_user = await client.post(
        f"/api/notifications/{foreign.id}/read",
        headers=_headers(owner_token),
    )
    first = await client.post(
        f"/api/notifications/{own.id}/read",
        headers=_headers(owner_token),
    )
    repeated = await client.post(
        f"/api/notifications/{own.id}/read",
        headers=_headers(owner_token),
    )

    assert cross_user.status_code == 200
    assert cross_user.json() == {"ok": True}
    assert first.json() == {"ok": True}
    assert repeated.json() == {"ok": True}

    owner_list = await client.get(
        "/api/notifications",
        headers=_headers(owner_token),
    )
    other_list = await client.get(
        "/api/notifications",
        headers=_headers(other_token),
    )
    assert owner_list.json()["unread"] == 0
    assert other_list.json()["unread"] == 1


async def test_read_all_updates_only_current_user(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, other_id = await _register(client, "other@example.com")
    await _create(session, user_id=owner_id, title="one", created_at=NOW)
    await _create(
        session,
        user_id=owner_id,
        title="two",
        created_at=NOW - timedelta(minutes=1),
    )
    await _create(session, user_id=other_id, title="foreign", created_at=NOW)
    await session.commit()

    response = await client.post(
        "/api/notifications/read-all",
        headers=_headers(owner_token),
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    owner_list = await client.get(
        "/api/notifications",
        headers=_headers(owner_token),
    )
    other_list = await client.get(
        "/api/notifications",
        headers=_headers(other_token),
    )
    assert owner_list.json()["unread"] == 0
    assert other_list.json()["unread"] == 1


async def test_delete_is_owner_scoped_and_idempotent(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, other_id = await _register(client, "other@example.com")
    own = await _create(
        session,
        user_id=owner_id,
        title="own",
        created_at=NOW,
    )
    foreign = await _create(
        session,
        user_id=other_id,
        title="foreign",
        created_at=NOW,
    )
    await session.commit()

    cross_user = await client.delete(
        f"/api/notifications/{foreign.id}",
        headers=_headers(owner_token),
    )
    first = await client.delete(
        f"/api/notifications/{own.id}",
        headers=_headers(owner_token),
    )
    repeated = await client.delete(
        f"/api/notifications/{own.id}",
        headers=_headers(owner_token),
    )

    assert cross_user.status_code == 200
    assert cross_user.json() == {"ok": True}
    assert first.json() == {"ok": True}
    assert repeated.json() == {"ok": True}
    owner_list = await client.get(
        "/api/notifications",
        headers=_headers(owner_token),
    )
    other_list = await client.get(
        "/api/notifications",
        headers=_headers(other_token),
    )
    assert owner_list.json()["notifications"] == []
    assert [item["id"] for item in other_list.json()["notifications"]] == [
        foreign.id
    ]
