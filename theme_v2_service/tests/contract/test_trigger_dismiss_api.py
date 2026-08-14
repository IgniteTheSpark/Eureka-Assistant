from datetime import datetime, timedelta

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.domains.triggers.models import TriggerExecution, TriggerTracker
from app.main import app

from tests.fakes.auth_helpers import register_user


NOW = datetime(2026, 7, 31, 10, 0, 0)


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> tuple[str, str]:
    body = await register_user(client, email, password="secret123")
    return body["token"], body["user"]["id"]


async def _execution(session, *, user_id: str, status: str = "available"):
    tracker = TriggerTracker(
        user_id=user_id,
        trigger_type="proactive_summary",
        scope_type="user_skill",
        scope_id="skill-1",
        cycle_started_at=NOW - timedelta(days=7),
    )
    session.add(tracker)
    await session.flush()
    execution = TriggerExecution(
        user_id=user_id,
        trigger_type="proactive_summary",
        workflow_type="report_generation",
        tracker_id=tracker.id,
        scope_type="user_skill",
        scope_id="skill-1",
        status=status,
        dedupe_key=f"proactive_summary:{tracker.id}:cycle-1",
        revision=1,
        payload_json={},
        first_fired_at=NOW,
        last_fired_at=NOW,
        workflow_run_id="run-1" if status == "consumed" else None,
    )
    session.add(execution)
    await session.flush()
    tracker.active_execution_id = execution.id
    await session.commit()
    return tracker, execution


async def test_dismiss_requires_auth_and_is_owner_scoped(client, session, monkeypatch):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    tracker, execution = await _execution(session, user_id=owner_id)
    monkeypatch.setattr("app.domains.triggers.api.utc_now", lambda: NOW)

    unauthorized = await client.post(
        f"/api/trigger-executions/{execution.id}/dismiss"
    )
    cross_user = await client.post(
        f"/api/trigger-executions/{execution.id}/dismiss",
        headers={"Authorization": f"Bearer {other_token}"},
    )
    response = await client.post(
        f"/api/trigger-executions/{execution.id}/dismiss",
        headers={"Authorization": f"Bearer {owner_token}"},
    )

    assert unauthorized.status_code == 401
    assert cross_user.status_code == 404
    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "status": "available",
        "workflow_run_id": None,
    }
    await session.refresh(tracker)
    assert tracker.dismissed_until == NOW + timedelta(days=7)


async def test_dismiss_returns_gone_for_expired_execution(client, session):
    token, user_id = await _register(client, "owner@example.com")
    _, execution = await _execution(session, user_id=user_id, status="expired")

    response = await client.post(
        f"/api/trigger-executions/{execution.id}/dismiss",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 410


async def test_dismiss_consumed_execution_returns_existing_run(client, session):
    token, user_id = await _register(client, "owner@example.com")
    _, execution = await _execution(session, user_id=user_id, status="consumed")

    response = await client.post(
        f"/api/trigger-executions/{execution.id}/dismiss",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "status": "consumed",
        "workflow_run_id": "run-1",
    }
