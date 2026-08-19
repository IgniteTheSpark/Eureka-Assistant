import asyncio
from datetime import datetime

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.db.models import Asset, UserSkill
from app.domains.reports.models import Report, ReportGenerationRun
from app.main import app
from tests.fakes.auth_helpers import register_user


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def _register(client: AsyncClient, email: str) -> tuple[dict[str, str], str]:
    body = await register_user(client, email, password="Secret123!")
    return (
        {"Authorization": f"Bearer {body['token']}"},
        body["user"]["id"],
    )


async def _report(session, *, user_id: str) -> Report:
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="completed",
        launch_context={},
        intent="训练复盘",
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        completed_at=datetime(2026, 8, 4, 10, 0, 0),
    )
    session.add(run)
    await session.flush()
    report = Report(
        user_id=user_id,
        generation_run_id=run.id,
        title="八月训练复盘",
        template_id="tennis_monthly_review",
        template_version="1.0.0",
        base_family="data_trend",
        content_md="训练节奏趋于稳定。",
        html="<html><body>训练节奏趋于稳定。</body></html>",
        spec_json={
            "template_id": "tennis_monthly_review",
            "template_version": "1.0.0",
            "base_family": "data_trend",
            "source_asset_ids": [],
            "unavailable_asset_ids": [],
            "field_bindings": {},
            "time_range": None,
            "external_sources": [],
            "web_policy": "none",
            "generated_file_ids": [],
            "surface": "surface-dashboard",
            "palette": "pal-dashboard",
            "seed": 0,
            "suggested_actions": [
                {
                    "id": "action-grounded",
                    "title": "复盘下一次训练",
                    "due_at": "2026-08-10T09:00:00+08:00",
                },
                {
                    "id": "action-second",
                    "title": "整理发球记录",
                    "due_at": None,
                },
            ],
            "presentation_version": "report_html_v2",
        },
        share_card_spec={
            "headline": "八月训练复盘",
            "summary": "训练节奏趋于稳定",
            "highlights": [],
            "time_range": "2026-08",
            "illustration_file_id": None,
        },
        tokens_used=0,
        gen_ms=0,
        created_at=datetime(2026, 8, 4, 10, 0, 0),
    )
    session.add(report)
    await session.flush()
    run.report_id = report.id
    await session.commit()
    return report


async def test_report_action_is_owner_scoped_idempotent_and_has_provenance(
    client,
    session,
):
    owner_headers, owner_id = await _register(client, "actions-owner@example.com")
    other_headers, _ = await _register(client, "actions-other@example.com")
    report = await _report(session, user_id=owner_id)

    listed = await client.get(
        f"/api/reports/{report.id}/actions", headers=owner_headers
    )
    cross = await client.get(
        f"/api/reports/{report.id}/actions", headers=other_headers
    )
    unknown = await client.post(
        f"/api/reports/{report.id}/actions/action-unknown",
        headers=owner_headers,
    )
    created = await client.post(
        f"/api/reports/{report.id}/actions/action-grounded",
        headers=owner_headers,
        json={"title": "恶意覆盖标题"},
    )
    repeated = await client.post(
        f"/api/reports/{report.id}/actions/action-grounded",
        headers=owner_headers,
    )

    assert listed.status_code == 200
    assert listed.json()["actions"][0] == {
        "id": "action-grounded",
        "title": "复盘下一次训练",
        "due_at": "2026-08-10T01:00:00Z",
        "created": False,
        "todo_asset_id": None,
    }
    assert cross.status_code == 404
    assert unknown.status_code == 404
    assert created.status_code == 200
    assert created.json()["created"] is True
    assert repeated.json() == {**created.json(), "created": False}

    asset_id = created.json()["todo_asset_id"]
    asset_response = await client.get(f"/api/assets/{asset_id}", headers=owner_headers)
    payload = asset_response.json()
    assert payload["payload"] == {
        "title": "复盘下一次训练",
        "due_date": "2026-08-10T09:00:00+08:00",
        "domain": "productivity",
        "status": "completed",
        "reminder_offsets_minutes": [15],
    }
    assert payload["source_report_id"] == report.id
    assert payload["source_report_action_id"] == "action-grounded"
    assert payload["source_report_title"] == "八月训练复盘"
    assert payload["effective_at"] == "2026-08-10T01:00:00Z"
    assert await session.scalar(
        select(func.count()).select_from(Asset).where(Asset.user_id == owner_id)
    ) == 1
    assert await session.scalar(
        select(func.count())
        .select_from(UserSkill)
        .where(UserSkill.user_id == owner_id, UserSkill.machine_name == "todo")
    ) == 1


async def test_concurrent_action_requests_create_one_todo(client, session):
    headers, user_id = await _register(client, "actions-race@example.com")
    report = await _report(session, user_id=user_id)

    first, second = await asyncio.gather(
        client.post(
            f"/api/reports/{report.id}/actions/action-second", headers=headers
        ),
        client.post(
            f"/api/reports/{report.id}/actions/action-second", headers=headers
        ),
    )

    assert first.status_code == 200
    assert second.status_code == 200
    assert {first.json()["created"], second.json()["created"]} == {False, True}
    assert first.json()["todo_asset_id"] == second.json()["todo_asset_id"]
    assert await session.scalar(
        select(func.count()).select_from(Asset).where(Asset.user_id == user_id)
    ) == 1


async def test_asset_list_includes_report_provenance(client, session):
    headers, user_id = await _register(client, "actions-list@example.com")
    report = await _report(session, user_id=user_id)
    await client.post(
        f"/api/reports/{report.id}/actions/action-second", headers=headers
    )

    listed = await client.get("/api/assets", headers=headers)

    assert listed.json()[0]["source_report_id"] == report.id
    assert listed.json()[0]["source_report_title"] == "八月训练复盘"
