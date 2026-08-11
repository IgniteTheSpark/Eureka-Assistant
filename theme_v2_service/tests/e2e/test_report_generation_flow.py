from io import BytesIO
from pathlib import Path

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from PIL import Image
from sqlalchemy import select

from app.db.models import WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.pipeline import report_pipeline_handler
from app.domains.reports.planner import PlannerResult, execute_report_planner_job
from app.domains.reports.providers import (
    GeneratedImage,
    GeneratedSuggestedAction,
    GeneratorResult,
)
from app.domains.reports.schemas import (
    CapabilityPolicy,
    EvidenceScope,
    IllustrationPolicy,
    ReportPlanOption,
)
from app.domains.reports.storage import LocalStorage
from app.domains.reports.templates import TemplateRegistry
from app.main import app
from tests.fakes.report_providers import (
    FakeGeneratorProvider,
    FakeIllustrationProvider,
    FakePlannerProvider,
    FakeWebSearchProvider,
)


TEMPLATES = Path(__file__).parents[2] / "report-templates"


@pytest_asyncio.fixture
async def client(session):
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://theme-v2.test",
    ) as http_client:
        yield http_client


async def test_report_flow_from_records_through_share_card_and_revocation(
    client,
    tmp_path,
):
    registered = await client.post(
        "/api/auth/register",
        json={"email": "report-e2e@example.com", "password": "secret1"},
    )
    token = registered.json()["token"]
    headers = {"Authorization": f"Bearer {token}"}
    skill_response = await client.post(
        "/api/user-skills",
        headers=headers,
        json={
            "machine_name": "journal",
            "display_name": "Journal",
            "domain": "reflection",
            "schema": {
                "type": "object",
                "x-data-capabilities": ["daily_log", "free_text"],
                "properties": {"note": {"type": "string"}},
            },
        },
    )
    skill_id = skill_response.json()["id"]
    asset_response = await client.post(
        "/api/assets",
        headers=headers,
        json={
            "user_skill_id": skill_id,
            "payload": {"note": "Finished the monthly reflection"},
        },
    )
    asset_id = asset_response.json()["id"]
    created = await client.post(
        "/api/report-generation-runs",
        headers=headers,
        json={
            "origin": "user_initiated",
            "intent": "Summarize this month",
            "skill_ids": [skill_id],
            "asset_ids": [asset_id],
        },
    )
    assert created.status_code == 200
    run_id = created.json()["id"]
    prepared = await client.post(
        f"/api/report-generation-runs/{run_id}/prepare-plan",
        headers=headers,
        json={"expected_revision": created.json()["scope_revision"]},
    )
    assert prepared.status_code == 200

    async with AsyncSessionFactory() as worker_session:
        run = await worker_session.get(ReportGenerationRun, run_id)
        planner_job = await worker_session.get(WorkflowJob, run.planner_job_id)
        planner_job.status = "running"
        planner_job.lease_owner = "e2e-worker"
        await worker_session.commit()
    option = ReportPlanOption(
        id="monthly-summary",
        recommended=True,
        title="Monthly reflection",
        summary="Review the selected journal records",
        report_goal="Summarize this month",
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        evidence_scope=EvidenceScope(
            skill_ids=[skill_id],
            asset_ids=[asset_id],
            counts_by_skill={skill_id: 1},
        ),
        field_bindings={"record.note": "payload.note"},
        web_search=CapabilityPolicy(policy="none"),
        illustration=IllustrationPolicy(policy="optional"),
        render_policy="report_html_v1",
    )
    assert await execute_report_planner_job(
        planner_job,
        provider=FakePlannerProvider(PlannerResult(options=[option])),
        registry=TemplateRegistry.load(TEMPLATES),
        session_factory=AsyncSessionFactory,
    )

    planned = await client.get(
        f"/api/report-generation-runs/{run_id}",
        headers=headers,
    )
    assert planned.json()["state"] == "awaiting_selection"
    generating = await client.post(
        f"/api/report-generation-runs/{run_id}/generate",
        headers=headers,
        json={
            "selected_option_id": "monthly-summary",
            "expected_plan_revision": planned.json()["plan_revision"],
        },
    )
    assert generating.json()["state"] == "generating"

    async with AsyncSessionFactory() as worker_session:
        run = await worker_session.get(ReportGenerationRun, run_id)
        pipeline_job = await worker_session.get(WorkflowJob, run.generation_job_id)
        pipeline_job.status = "running"
        pipeline_job.lease_owner = "e2e-worker"
        await worker_session.commit()
    pipeline = report_pipeline_handler(
        generator=FakeGeneratorProvider(
            GeneratorResult(
                content_md=f"Monthly reflection complete. [evidence:{asset_id}]",
                suggested_actions=[
                    GeneratedSuggestedAction(title="安排下一次月度复盘")
                ],
                share_card_spec={
                    "headline": "Monthly reflection",
                    "summary": "The month is now easier to understand.",
                    "highlights": ["Reflection complete"],
                    "time_range": "July 2026",
                },
            )
        ),
        web_search=FakeWebSearchProvider(),
        illustration=FakeIllustrationProvider(
            GeneratedImage(data=b"unused", mime_type="image/png")
        ),
        registry=TemplateRegistry.load(TEMPLATES),
        storage=LocalStorage(tmp_path / "pipeline-media"),
        session_factory=AsyncSessionFactory,
    )
    await pipeline(pipeline_job)

    completed = await client.get(
        f"/api/report-generation-runs/{run_id}",
        headers=headers,
    )
    assert completed.json()["state"] == "completed"
    report_id = completed.json()["report_id"]
    private_report = await client.get(f"/api/reports/{report_id}", headers=headers)
    assert private_report.status_code == 200
    assert "[evidence:" not in private_report.json()["content_md"]
    assert "[evidence:" not in private_report.json()["html"]
    assert private_report.json()["spec"]["citations"]
    assert private_report.json()["spec"]["suggested_actions"][0]["title"] == (
        "安排下一次月度复盘"
    )

    actions = await client.get(
        f"/api/reports/{report_id}/actions",
        headers=headers,
    )
    action_id = actions.json()["actions"][0]["id"]
    created_action = await client.post(
        f"/api/reports/{report_id}/actions/{action_id}",
        headers=headers,
    )
    repeated_action = await client.post(
        f"/api/reports/{report_id}/actions/{action_id}",
        headers=headers,
    )
    assert created_action.json()["created"] is True
    assert repeated_action.json() == {
        **created_action.json(),
        "created": False,
    }
    todo_id = created_action.json()["todo_asset_id"]
    todo = await client.get(f"/api/assets/{todo_id}", headers=headers)
    assert todo.json()["source_report_id"] == report_id
    assert todo.json()["source_report_action_id"] == action_id
    assert todo.json()["source_report_title"] == "Monthly reflection"

    created_share = await client.post(
        f"/api/reports/{report_id}/shares",
        headers=headers,
    )
    share_id = created_share.json()["share_id"]
    share_token = created_share.json()["url"].rsplit("/", 1)[-1]
    public = await client.get(f"/api/public/report-shares/{share_token}")
    card = await client.get(public.json()["share_card_url"])
    assert public.status_code == 200
    assert Image.open(BytesIO(card.content)).size == (1080, 1440)

    revoked = await client.delete(
        f"/api/report-shares/{share_id}",
        headers=headers,
    )
    assert revoked.status_code == 200
    assert (await client.get(f"/r/{share_token}")).status_code == 404
