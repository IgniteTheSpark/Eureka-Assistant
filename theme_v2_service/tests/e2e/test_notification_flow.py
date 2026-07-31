import asyncio

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from starlette.requests import Request

from app.auth.dependencies import get_current_user_id
from app.db.base import utc_now
from app.db.session import AsyncSessionFactory
from app.domains.notifications.api import notification_stream
from app.domains.notifications.outbox import dispatch_one
from app.domains.notifications.schemas import NotificationCreate
from app.domains.notifications.service import create_notification
from app.domains.notifications.subscribers import SubscriberRegistry
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _authenticated_request(client: AsyncClient) -> tuple[Request, str]:
    registered = await client.post(
        "/api/auth/register",
        json={"email": "owner@example.com", "password": "secret1"},
    )
    assert registered.status_code == 200
    token = registered.json()["token"]
    request = Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/api/notifications/stream",
            "headers": [(b"authorization", f"Bearer {token}".encode())],
            "app": app,
        }
    )
    assert get_current_user_id(request) == registered.json()["user"]["id"]
    return request, token


async def test_worker_notification_reaches_sse_and_survives_reconnect(client):
    request, token = await _authenticated_request(client)
    user_id = get_current_user_id(request)
    registry = SubscriberRegistry()
    app.state.notification_subscribers = registry

    response = await notification_stream(request=request, user_id=user_id)
    stream = response.body_iterator
    assert await anext(stream) == ": connected\n\n"

    async with AsyncSessionFactory() as worker_session:
        notification = await create_notification(
            worker_session,
            NotificationCreate(
                user_id=user_id,
                type="report_done",
                title="Weekly report ready",
                link="/reports/run-42",
            ),
        )
        await worker_session.commit()
        notification_id = notification.id

    assert await dispatch_one(
        AsyncSessionFactory,
        registry,
        now=utc_now(),
    )
    frame = await anext(stream)
    assert "event: notification" in frame
    assert f'"id":"{notification_id}"' in frame

    history = await client.get(
        "/api/notifications",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert history.status_code == 200
    assert [item["id"] for item in history.json()["notifications"]] == [
        notification_id
    ]
    await stream.aclose()

    reconnected = await notification_stream(request=request, user_id=user_id)
    reconnect_stream = reconnected.body_iterator
    assert await anext(reconnect_stream) == ": connected\n\n"
    with pytest.raises(TimeoutError):
        await asyncio.wait_for(anext(reconnect_stream), timeout=0.01)

    recovered = await client.get(
        "/api/notifications",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert [item["id"] for item in recovered.json()["notifications"]] == [
        notification_id
    ]
