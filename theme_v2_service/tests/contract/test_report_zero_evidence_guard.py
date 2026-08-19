from datetime import datetime

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.domains.reports.models import ReportGenerationRun
from tests.fakes.auth_helpers import register_user
from app.main import app


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def test_user_report_without_evidence_stays_at_plan_selection(client, session):
    registered = await register_user(client, "empty-report@example.com")
    user_id = registered["user"]["id"]
    headers = {"Authorization": f"Bearer {registered['token']}"}
    option = {
        "id": "daily",
        "recommended": True,
        "title": "今日执行报告",
        "summary": "整理今天的日程与代办",
        "report_goal": "今日执行复盘",
        "template_id": "general_period_review",
        "template_version": "1.0.0",
        "base_family": "theme_synthesis",
        "evidence_scope": {},
        "field_bindings": {},
        "web_search": {"policy": "none", "reason": None},
        "illustration": {"policy": "optional", "reason": None},
        "render_policy": "report_html_v1",
    }
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="awaiting_selection",
        launch_context={},
        intent="生成今日执行报告",
        answers={},
        evidence_scope={},
        pending_decision={
            "type": "plan_selection",
            "recommended_option_id": "daily",
        },
        plan_options=[option],
        plan_draft={
            "selected_option_id": "daily",
            "evidence_scope": {},
            "public_research_scope": {},
            "blockers": [],
        },
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
        created_at=datetime(2026, 8, 9, 9, 0, 0),
    )
    session.add(run)
    await session.commit()

    response = await client.post(
        f"/api/report-generation-runs/{run.id}/generate",
        headers=headers,
        json={"selected_option_id": "daily", "expected_plan_revision": 0},
    )

    assert response.status_code == 409
    await session.refresh(run)
    assert run.state == "awaiting_selection"
    assert run.generation_job_id is None
