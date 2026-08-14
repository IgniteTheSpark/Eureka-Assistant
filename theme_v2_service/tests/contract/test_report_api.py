from pathlib import Path

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.db.models import WorkflowJob
from app.domains.reports.models import File, ReportGenerationRun
from app.domains.reports.service import CompletedReportData, persist_completed_report
from app.domains.reports.storage import LocalStorage, persist_owned_file
from app.main import app

from tests.fakes.auth_helpers import register_user


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


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _completed_report(session, *, user_id: str):
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="generating",
        active_stage="persist",
        launch_context={},
        intent="Summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        execution_plan={},
        template_id="general_period_review",
        template_version="1.0.0",
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_pipeline",
        status="running",
        lease_owner="worker-1",
    )
    session.add(job)
    await session.flush()
    run.generation_job_id = job.id
    report = await persist_completed_report(
        session,
        run_id=run.id,
        job_id=job.id,
        lease_owner="worker-1",
        data=CompletedReportData(
            title="Private report",
            content_md="# Private report\n\nVisible to owner.",
            html="<html><body>Private viewer</body></html>",
            spec_json={
                "template_id": "general_period_review",
                "template_version": "1.0.0",
                "base_family": "theme_synthesis",
                "source_asset_ids": [],
                "unavailable_asset_ids": [],
                "field_bindings": {},
                "time_range": None,
                "external_sources": [],
                "web_policy": "none",
                "generated_file_ids": [],
                "surface": "report",
                "palette": "calm",
                "seed": 1,
            },
            share_card_spec={
                "headline": "Private report",
                "summary": "Owner only",
                "highlights": [],
                "time_range": "2026-07",
                "illustration_file_id": None,
            },
            tokens_used=10,
            gen_ms=20,
        ),
    )
    await session.commit()
    return run, report


async def test_report_list_detail_viewer_and_active_run_exclusion(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    run, report = await _completed_report(session, user_id=owner_id)

    listed = await client.get("/api/reports", headers=_headers(owner_token))
    detail = await client.get(
        f"/api/reports/{report.id}", headers=_headers(owner_token)
    )
    viewer = await client.get(
        f"/app/reports/{report.id}", headers=_headers(owner_token)
    )
    active = await client.get(
        "/api/report-generation-runs",
        params={"active": True},
        headers=_headers(owner_token),
    )
    cross_detail = await client.get(
        f"/api/reports/{report.id}", headers=_headers(other_token)
    )
    cross_viewer = await client.get(
        f"/app/reports/{report.id}", headers=_headers(other_token)
    )

    assert [item["id"] for item in listed.json()] == [report.id]
    assert detail.json()["content_md"].startswith("# Private")
    assert detail.json()["revision"] == 1
    assert detail.json()["illustration_status"] == "not_required"
    assert detail.json()["updated_at"].endswith("Z")
    assert "job" not in detail.json()
    assert viewer.status_code == 200
    assert "Private viewer" in viewer.text
    assert active.json() == []
    assert run.state == "completed"
    assert cross_detail.status_code == 404
    assert cross_viewer.status_code == 404


async def test_private_file_requires_owner(client, session):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    storage = LocalStorage(Path(get_settings().media_root))
    file = await persist_owned_file(
        session,
        storage=storage,
        user_id=owner_id,
        purpose="report_illustration",
        key=f"tests/{owner_id}/private.png",
        content=b"private-image",
        mime_type="image/png",
    )
    await session.commit()

    own = await client.get(f"/api/files/{file.id}", headers=_headers(owner_token))
    cross = await client.get(f"/api/files/{file.id}", headers=_headers(other_token))
    missing = await client.get("/api/files/missing", headers=_headers(owner_token))

    assert own.status_code == 200
    assert own.content == b"private-image"
    assert own.headers["content-type"] == "image/png"
    assert cross.status_code == 404
    assert missing.status_code == 404


async def test_report_action_contract_accepts_only_path_action_id(client):
    schema = (await client.get("/openapi.json")).json()

    list_operation = schema["paths"]["/api/reports/{report_id}/actions"]["get"]
    create_operation = schema["paths"][
        "/api/reports/{report_id}/actions/{action_id}"
    ]["post"]
    assert "requestBody" not in list_operation
    assert "requestBody" not in create_operation
