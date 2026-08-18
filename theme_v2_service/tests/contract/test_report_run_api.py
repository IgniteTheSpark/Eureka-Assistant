from datetime import datetime, timedelta

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.db.models import Asset, Contact, Event, UserSkill, WorkflowJob
from app.domains.reports.models import ReportGenerationRun
from app.domains.triggers.models import TriggerExecution
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
    response = await client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret1"},
    )
    assert response.status_code == 200
    return response.json()["token"], response.json()["user"]["id"]


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _execution(session, *, user_id: str, status: str = "available"):
    execution = TriggerExecution(
        user_id=user_id,
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        tracker_id=None,
        scope_type="event",
        scope_id="event-1",
        status=status,
        dedupe_key=f"pre_event_report:event-1:{status}:{user_id}",
        revision=1,
        payload_json={
            "event_id": "event-1",
            "event_title": "Private meeting",
        },
        first_fired_at=NOW,
        last_fired_at=NOW,
        expires_at=NOW + timedelta(hours=1),
    )
    session.add(execution)
    await session.commit()
    return execution


def _option() -> dict:
    return {
        "id": "option-1",
        "recommended": True,
        "title": "Visible title",
        "summary": "Visible summary",
        "report_goal": "Visible goal",
        "template_id": "secret-template",
        "template_version": "1.0.0",
        "base_family": "theme_synthesis",
        "evidence_scope": {
            "time_range": None,
            "skill_ids": [],
            "asset_ids": [],
            "counts_by_skill": {},
        },
        "field_bindings": {"secret_key": "payload.private"},
        "web_search": {"policy": "none", "reason": None},
        "illustration": {"policy": "optional", "reason": "Visible reason"},
        "render_policy": "report_html_v1",
    }


async def _awaiting_run(session, *, user_id: str) -> ReportGenerationRun:
    run = ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="awaiting_selection",
        launch_context={
            "event_id": "event-1",
            "private": "must-not-leak",
        },
        intent="Create a report",
        answers={},
        evidence_scope={},
        pending_decision={
            "type": "plan_selection",
            "recommended_option_id": "option-1",
        },
        plan_options=[_option()],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.commit()
    return run


async def test_manual_run_requires_auth_and_appears_in_active_list(client):
    unauthorized = await client.post(
        "/api/report-generation-runs",
        json={"origin": "user_initiated", "intent": "Summary"},
    )
    assert unauthorized.status_code == 401
    token, _ = await _register(client, "owner@example.com")

    created = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={
            "origin": "user_initiated",
            "intent": "Summary",
            "skill_ids": [],
            "asset_ids": [],
        },
    )
    listed = await client.get(
        "/api/report-generation-runs",
        headers=_headers(token),
        params={"active": True},
    )

    assert created.status_code == 200
    assert created.json()["state"] == "awaiting_selection"
    assert created.json()["scope_adapter"] == "generic"
    assert created.json()["pending_decision"] == {
        "type": "scope_confirmation",
        "questions": [],
        "adapter_kind": "generic",
    }
    assert created.json()["job_id"] is None
    assert [item["id"] for item in listed.json()] == [created.json()["id"]]


async def test_pre_event_scope_lists_three_future_meetings_and_only_plans_after_confirmation(
    client,
    session,
    monkeypatch,
):
    token, user_id = await _register(client, "pre-event@example.com")
    monkeypatch.setattr("app.domains.reports.service.utc_now", lambda: NOW)
    events = []
    for index in range(4):
        event = Event(
            user_id=user_id,
            title=f"会议 {index + 1}",
            description=f"备注 {index + 1}",
            start_at=NOW + timedelta(hours=index + 1),
            end_at=NOW + timedelta(hours=index + 2),
            all_day=False,
        )
        events.append(event)
        session.add(event)
    await session.commit()
    event_ids = [event.id for event in events]

    created = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={"origin": "user_initiated", "intent": "会前调研"},
    )
    run_id = created.json()["id"]
    candidates = await client.get(
        f"/api/report-generation-runs/{run_id}/scope-candidates",
        headers=_headers(token),
    )

    assert created.status_code == 200
    assert created.json()["scope_adapter"] == "pre_event_briefing"
    assert candidates.status_code == 200
    assert [item["reference"]["id"] for item in candidates.json()["events"]] == [
        *event_ids[:3]
    ]
    assert candidates.json()["events"][0]["notes"] == "备注 1"
    assert await session.scalar(
        select(func.count())
        .select_from(WorkflowJob)
        .where(WorkflowJob.job_type == "report_planner")
    ) == 0

    updated = await client.put(
        f"/api/report-generation-runs/{run_id}/scope-draft",
        headers=_headers(token),
        json={
            "expected_revision": 0,
            "draft": {
                "adapter_kind": "pre_event_briefing",
                "primary_reference": {"kind": "event", "id": event_ids[0]},
                "attention_focus": ["对方公开背景"],
                "additional_focus": "重点看欧洲足球体系",
            },
        },
    )
    assert updated.status_code == 200
    assert updated.json()["scope_revision"] == 1
    assert updated.json()["evidence_scope"]["references"] == [
        {"kind": "event", "id": event_ids[0]}
    ]

    prepared = await client.post(
        f"/api/report-generation-runs/{run_id}/prepare-plan",
        headers=_headers(token),
        json={"expected_revision": 1},
    )
    assert prepared.status_code == 200
    assert prepared.json()["state"] == "planning"
    assert prepared.json()["active_stage"] == "intake"
    await session.rollback()
    job = await session.get(WorkflowJob, prepared.json()["job_id"])
    assert job.job_type == "report_planner"
    run = await session.get(ReportGenerationRun, run_id)
    assert run.launch_context["event_id"] == event_ids[0]
    assert run.scope_hash is not None
    assert run.plan_scope_hash is None


async def test_scope_candidates_refetch_for_explicit_custom_range(
    client,
    session,
    monkeypatch,
):
    token, user_id = await _register(client, "custom-range@example.com")
    monkeypatch.setattr("app.domains.reports.service.utc_now", lambda: NOW)
    skill = UserSkill(
        user_id=user_id,
        machine_name="running_custom_range",
        display_name="跑步记录",
        schema_json={
            "type": "object",
            "properties": {"distance": {"type": "number"}},
        },
    )
    session.add(skill)
    await session.flush()
    older = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"distance": 12},
        effective_at=NOW - timedelta(days=45),
    )
    recent = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"distance": 5},
        effective_at=NOW - timedelta(days=5),
    )
    session.add_all([older, recent])
    await session.commit()
    created = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={"origin": "user_initiated", "intent": "总结过去 30 天的跑步记录"},
    )

    response = await client.get(
        f"/api/report-generation-runs/{created.json()['id']}/scope-candidates",
        headers=_headers(token),
        params={
            "from": "2026-06-01T00:00:00+08:00",
            "to": "2026-08-01T00:00:00+08:00",
        },
    )

    assert response.status_code == 200
    ids = [
        record["reference"]["id"]
        for group in response.json()["record_groups"]
        for record in group["records"]
    ]
    assert ids == [older.id, recent.id]
    assert response.json()["default_scope"]["time_range"] == {
        "from": "2026-06-01T00:00:00+08:00",
        "to": "2026-08-01T00:00:00+08:00",
    }


async def test_prepare_returns_stable_incompatible_presentation_blocker(
    client,
    session,
):
    token, user_id = await _register(client, "presentation-blocker@example.com")
    skill = UserSkill(
        user_id=user_id,
        machine_name="measurements",
        display_name="数据记录",
        schema_json={
            "type": "object",
            "x-data-capabilities": ["time_series_measurement"],
            "properties": {"value": {"type": "number"}},
        },
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"value": 1},
    )
    session.add(asset)
    await session.commit()
    created = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={
            "origin": "user_initiated",
            "intent": "总结数据",
            "skill_ids": [skill.id],
            "asset_ids": [asset.id],
        },
    )
    run_id = created.json()["id"]
    updated = await client.put(
        f"/api/report-generation-runs/{run_id}/scope-draft",
        headers=_headers(token),
        json={
            "expected_revision": 0,
            "draft": {
                **created.json()["scope_draft"],
                "presentation_preference": {"family": "briefing_research"},
            },
        },
    )
    assert updated.status_code == 200

    response = await client.post(
        f"/api/report-generation-runs/{run_id}/prepare-plan",
        headers=_headers(token),
        json={"expected_revision": 1},
    )

    assert response.status_code == 409
    assert response.json()["detail"]["code"] == "presentation_incompatible"


async def test_scope_update_rejects_stale_revision_and_cross_user_reference(
    client,
    session,
):
    token, _ = await _register(client, "scope-owner@example.com")
    _, other_user_id = await _register(client, "scope-other@example.com")
    other_event = Event(
        user_id=other_user_id,
        title="Other private meeting",
        start_at=NOW + timedelta(hours=1),
        end_at=NOW + timedelta(hours=2),
        all_day=False,
    )
    session.add(other_event)
    await session.commit()
    created = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={"origin": "user_initiated", "intent": "会前调研"},
    )
    run_id = created.json()["id"]
    payload = {
        "draft": {
            "adapter_kind": "pre_event_briefing",
            "primary_reference": {"kind": "event", "id": other_event.id},
        }
    }

    stale = await client.put(
        f"/api/report-generation-runs/{run_id}/scope-draft",
        headers=_headers(token),
        json={**payload, "expected_revision": 1},
    )
    forbidden = await client.put(
        f"/api/report-generation-runs/{run_id}/scope-draft",
        headers=_headers(token),
        json={**payload, "expected_revision": 0},
    )

    assert stale.status_code == 409
    assert forbidden.status_code == 409


async def test_trigger_run_consumes_once_and_hides_cross_user(client, session, monkeypatch):
    owner_token, owner_id = await _register(client, "owner@example.com")
    other_token, _ = await _register(client, "other@example.com")
    execution = await _execution(session, user_id=owner_id)
    monkeypatch.setattr("app.domains.reports.service.utc_now", lambda: NOW)

    cross_user = await client.post(
        "/api/report-generation-runs",
        headers=_headers(other_token),
        json={"origin": "trigger", "trigger_execution_id": execution.id},
    )
    first = await client.post(
        "/api/report-generation-runs",
        headers=_headers(owner_token),
        json={"origin": "trigger", "trigger_execution_id": execution.id},
    )
    repeated = await client.post(
        "/api/report-generation-runs",
        headers=_headers(owner_token),
        json={"origin": "trigger", "trigger_execution_id": execution.id},
    )

    assert cross_user.status_code == 404
    assert first.status_code == 200
    assert repeated.status_code == 200
    assert repeated.json()["id"] == first.json()["id"]
    await session.refresh(execution)
    assert execution.status == "consumed"
    assert execution.workflow_run_id == first.json()["id"]
    run = await session.get(ReportGenerationRun, first.json()["id"])
    assert run.launch_context["event_title"] == "Private meeting"


async def test_expired_trigger_is_gone_and_unclicked_is_not_a_run(client, session):
    token, user_id = await _register(client, "owner@example.com")
    unclicked = await _execution(session, user_id=user_id)
    expired = await _execution(session, user_id=user_id, status="expired")

    listed = await client.get(
        "/api/report-generation-runs",
        headers=_headers(token),
        params={"active": True},
    )
    response = await client.post(
        "/api/report-generation-runs",
        headers=_headers(token),
        json={"origin": "trigger", "trigger_execution_id": expired.id},
    )

    assert listed.json() == []
    assert response.status_code == 410
    assert unclicked.workflow_run_id is None


async def test_decision_replans_and_generate_is_idempotent(client, session):
    token, user_id = await _register(client, "owner@example.com")
    run = await _awaiting_run(session, user_id=user_id)

    decision = await client.post(
        f"/api/report-generation-runs/{run.id}/decision",
        headers=_headers(token),
        json={"answers": {"goal": "updated"}},
    )
    assert decision.status_code == 200
    assert decision.json()["state"] == "planning"
    await session.refresh(run)
    first_planner_job = run.planner_job_id
    assert first_planner_job is not None

    run.state = "awaiting_selection"
    run.pending_decision = {
        "type": "plan_selection",
        "recommended_option_id": "option-1",
    }
    run.plan_options = [_option()]
    await session.commit()

    first = await client.post(
        f"/api/report-generation-runs/{run.id}/generate",
        headers=_headers(token),
        json={"selected_option_id": "option-1", "expected_plan_revision": 0},
    )
    repeated = await client.post(
        f"/api/report-generation-runs/{run.id}/generate",
        headers=_headers(token),
        json={"selected_option_id": "option-1", "expected_plan_revision": 0},
    )

    assert first.status_code == 200
    assert repeated.json()["job_id"] == first.json()["job_id"]
    assert first.json()["state"] == "generating"
    serialized = str(first.json())
    for secret in (
        "secret-template",
        "secret_key",
        "payload.private",
        "must-not-leak",
        "theme_synthesis",
    ):
        assert secret not in serialized
    await session.refresh(run)
    assert run.planner_job_id == first_planner_job
    assert run.generation_job_id != first_planner_job
    assert await session.scalar(
        select(func.count())
        .select_from(WorkflowJob)
        .where(WorkflowJob.job_type == "report_pipeline")
    ) == 1


async def test_generate_rejects_a_plan_built_from_an_old_scope(client, session):
    token, user_id = await _register(client, "stale-plan@example.com")
    run = await _awaiting_run(session, user_id=user_id)
    run.scope_hash = "new-scope"
    run.plan_scope_hash = "old-scope"
    await session.commit()

    response = await client.post(
        f"/api/report-generation-runs/{run.id}/generate",
        headers=_headers(token),
        json={"selected_option_id": "option-1", "expected_plan_revision": 0},
    )

    assert response.status_code == 409
    assert "scope" in response.json()["detail"]


async def test_cancelled_and_completed_runs_reject_mutation(client, session):
    token, user_id = await _register(client, "owner@example.com")
    cancelled = await _awaiting_run(session, user_id=user_id)
    cancelled.state = "cancelled"
    completed = await _awaiting_run(session, user_id=user_id)
    completed.state = "completed"
    completed.report_id = "report-1"
    completed.completed_at = NOW
    await session.commit()

    cancelled_response = await client.post(
        f"/api/report-generation-runs/{cancelled.id}/generate",
        headers=_headers(token),
        json={"selected_option_id": "option-1", "expected_plan_revision": 0},
    )
    completed_response = await client.post(
        f"/api/report-generation-runs/{completed.id}/decision",
        headers=_headers(token),
        json={"answers": {}},
    )

    assert cancelled_response.status_code == 409
    assert completed_response.status_code == 409


async def test_plan_draft_updates_are_revisioned_and_person_scope_is_blocked(
    client,
    session,
):
    token, user_id = await _register(client, "draft@example.com")
    run = await _awaiting_run(session, user_id=user_id)
    run.plan_revision = 2
    run.plan_draft = {
        "selected_option_id": "option-1",
        "attention_questions": [],
        "additional_focus": "",
        "evidence_scope": {},
        "public_research_scope": {},
        "blockers": [],
    }
    await session.commit()
    command = {
        "selected_option_id": "option-1",
        "attention_questions": ["Kevin 的公开职业背景是什么？"],
        "additional_focus": "",
        "evidence_scope": {},
        "public_research_scope": {
            "entities": [
                {
                    "id": "kevin",
                    "kind": "person",
                    "name": "Kevin",
                }
            ],
            "questions": ["公开职业背景"],
            "freshness": "current",
        },
    }

    stale = await client.put(
        f"/api/report-generation-runs/{run.id}/plan-draft",
        headers=_headers(token),
        json={**command, "expected_revision": 1},
    )
    updated = await client.put(
        f"/api/report-generation-runs/{run.id}/plan-draft",
        headers=_headers(token),
        json={**command, "expected_revision": 2},
    )

    assert stale.status_code == 409
    assert updated.status_code == 200
    assert updated.json()["plan_revision"] == 3
    assert updated.json()["state"] == "awaiting_selection"
    assert updated.json()["plan_draft"]["blockers"][0]["code"] == "ambiguous_person"
    blocked_generate = await client.post(
        f"/api/report-generation-runs/{run.id}/generate",
        headers=_headers(token),
        json={"selected_option_id": "option-1", "expected_plan_revision": 3},
    )
    assert blocked_generate.status_code == 409


async def test_additional_focus_enqueues_scope_resolution(client, session):
    token, user_id = await _register(client, "scope@example.com")
    run = await _awaiting_run(session, user_id=user_id)

    response = await client.put(
        f"/api/report-generation-runs/{run.id}/plan-draft",
        headers=_headers(token),
        json={
            "expected_revision": 0,
            "selected_option_id": "option-1",
            "attention_questions": [],
            "additional_focus": "补充 Kevin（Eureka CEO）的公开职业背景",
            "evidence_scope": {},
            "public_research_scope": {
                "entities": [
                    {
                        "id": "kevin",
                        "kind": "person",
                        "name": "Kevin",
                        "qualifier": "Eureka CEO",
                    }
                ],
                "questions": ["公开职业背景"],
            },
        },
    )

    assert response.status_code == 200
    assert response.json()["state"] == "planning"
    assert response.json()["active_stage"] == "scope_resolution"
    job = await session.get(WorkflowJob, response.json()["job_id"])
    assert job.job_type == "report_scope_resolution"
    assert job.checkpoint_json == {"plan_revision": 1}


async def test_evidence_options_unify_owned_assets_events_and_contacts(client, session):
    token, user_id = await _register(client, "picker@example.com")
    skill = UserSkill(
        user_id=user_id,
        machine_name="running",
        display_name="跑步训练",
        description=None,
        domain="health",
        schema_json={"type": "object"},
        render_spec_json={"icon": "🏃"},
    )
    session.add(skill)
    await session.flush()
    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"title": "周末长跑"},
    )
    event = Event(
        user_id=user_id,
        title="与 Kevin 讨论球队建设",
        start_at=NOW,
        end_at=NOW + timedelta(hours=1),
        all_day=False,
    )
    contact = Contact(
        user_id=user_id,
        name="Kevin",
        company="Eureka",
        title="CEO",
        notes_json=[],
        socials_json={},
    )
    other = Contact(
        user_id="other-user",
        name="Kevin Secret",
        notes_json=[],
        socials_json={},
    )
    session.add_all([asset, event, contact, other])
    await session.commit()

    all_response = await client.get(
        "/api/report-generation-runs/evidence-options",
        headers=_headers(token),
    )
    contacts_response = await client.get(
        "/api/report-generation-runs/evidence-options",
        headers=_headers(token),
        params={"type": "contact", "q": "Kevin"},
    )

    assert all_response.status_code == 200
    assert {
        (item["reference"]["kind"], item["reference"]["id"])
        for item in all_response.json()["items"]
    } == {("asset", asset.id), ("event", event.id), ("contact", contact.id)}
    assert contacts_response.status_code == 200
    assert [item["reference"]["id"] for item in contacts_response.json()["items"]] == [
        contact.id
    ]
    assert {item["label"] for item in all_response.json()["filters"]} >= {
        "全部",
        "日程",
        "联系人",
        "跑步训练",
    }
