from types import SimpleNamespace

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from starlette.requests import Request

from app.domains.notifications.api import notification_stream
from app.domains.notifications.subscribers import SubscriberRegistry
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def test_stream_requires_auth(client):
    response = await client.get("/api/notifications/stream")

    assert response.status_code == 401


async def test_stream_emits_connected_then_notification_and_unregisters():
    registry = SubscriberRegistry()
    test_app = SimpleNamespace(
        state=SimpleNamespace(notification_subscribers=registry)
    )
    request = Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/api/notifications/stream",
            "headers": [],
            "app": test_app,
        }
    )

    response = await notification_stream(request=request, user_id="user-1")
    stream = response.body_iterator

    assert response.media_type == "text/event-stream"
    assert response.headers["cache-control"] == "no-cache"
    assert response.headers["x-accel-buffering"] == "no"
    assert await anext(stream) == ": connected\n\n"

    registry.publish("user-1", {"id": "n1"})
    assert await anext(stream) == (
        'event: notification\n'
        'data: {"id":"n1"}\n\n'
    )

    await stream.aclose()
    assert "user-1" not in registry._subscribers


async def test_api_lifespan_owns_one_registry_and_dispatcher():
    async with app.router.lifespan_context(app):
        registry = app.state.notification_subscribers
        task = app.state.notification_dispatcher_task

        assert isinstance(registry, SubscriberRegistry)
        assert not task.done()

    assert task.done()
