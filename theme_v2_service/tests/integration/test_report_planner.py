from datetime import datetime
from pathlib import Path

import pytest
from pydantic import ValidationError
from sqlalchemy import func, select

from app.db.models import Asset, Contact, Event, EventAttendee, UserSkill, WorkflowJob
from app.db.session import AsyncSessionFactory
from app.domains.notifications.models import Notification, OutboxEvent
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.providers import RetryableProviderError
from app.domains.reports.planner import (
    InvalidPlannerResult,
    PlannerLimits,
    PlannerResult,
    build_planner_request,
    execute_report_planner_job,
    persist_planner_result,
    validate_planner_result,
)
from app.domains.reports.planner_tools import PlannerTools
from app.domains.reports.schemas import (
    CapabilityPolicy,
    ClarificationQuestion,
    EvidenceScope,
    IllustrationPolicy,
    PublicResearchBrief,
    ResearchEntity,
    ReportPlanOption,
)
from app.domains.reports.templates import TemplateRegistry


TEMPLATES = Path(__file__).parents[2] / "report-templates"


class FakePlannerProvider:
    def __init__(self, result: PlannerResult) -> None:
        self.result = result
        self.calls = 0
        self.request = None

    async def plan(self, request):
        self.calls += 1
        self.request = request
        return self.result


class FailingPlannerProvider:
    async def plan(self, request):
        raise RetryableProviderError("private provider detail")


def _skill(
    *,
    user_id: str,
    name: str,
    domain: str = "growth",
    capabilities: list[str] | None = None,
) -> UserSkill:
    return UserSkill(
        user_id=user_id,
        machine_name=name.lower().replace(" ", "_"),
        display_name=name,
        description=f"Records for {name}",
        domain=domain,
        schema_json={
            "type": "object",
            "x-data-capabilities": capabilities or ["daily_log"],
            "properties": {
                "measurement": {"type": "number"},
                "note": {"type": "string"},
            },
        },
    )


def _asset(*, user_id: str, skill: UserSkill, index: int) -> Asset:
    return Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"measurement": index, "note": f"private-{index}"},
    )


def _run(*, user_id: str, skill: UserSkill, asset: Asset) -> ReportGenerationRun:
    return ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="planning",
        active_stage="intake",
        launch_context={},
        intent="总结最近的变化",
        answers={},
        evidence_scope={
            "time_range": None,
            "skill_ids": [skill.id],
            "asset_ids": [asset.id],
            "counts_by_skill": {},
        },
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )


def _option(
    *,
    skill_ids: list[str],
    asset_ids: list[str],
    option_id: str = "primary",
) -> ReportPlanOption:
    return ReportPlanOption(
        id=option_id,
        recommended=True,
        title="阶段成长总结",
        summary="根据现有记录总结变化",
        report_goal="识别已有记录中的变化和后续观察点",
        template_id="child_growth_review",
        template_version="1.0.0",
        base_family="professional_evaluation",
        evidence_scope=EvidenceScope(
            skill_ids=skill_ids,
            asset_ids=asset_ids,
            counts_by_skill={skill_id: 1 for skill_id in skill_ids},
        ),
        field_bindings={"measurement.value": "payload.measurement"},
        web_search=CapabilityPolicy(policy="authoritative_only"),
        illustration=IllustrationPolicy(policy="optional"),
        render_policy="report_html_v1",
    )


async def test_pre_event_plan_preserves_private_context_and_public_entities(session):
    contact = Contact(
        user_id="user-1",
        name="Kevin",
        company="Eureka",
        title="CEO",
        notes_json=["只在内部使用的会前备注"],
        socials_json={},
    )
    event = Event(
        user_id="user-1",
        title="球队建设情况讨论",
        description="比较皇家马德里和巴塞罗那的真实阵容，并讨论内部预算安排。",
        location="会议室",
        start_at=datetime(2026, 8, 8, 15, 0),
        end_at=datetime(2026, 8, 8, 16, 0),
        all_day=False,
    )
    session.add_all([contact, event])
    await session.flush()
    session.add(
        EventAttendee(
            event_id=event.id,
            contact_id=contact.id,
            name_raw="Kevin",
            role="attendee",
        )
    )
    run = ReportGenerationRun(
        user_id="user-1",
        origin="trigger",
        state="planning",
        active_stage="intake",
        launch_context={"event_id": event.id},
        intent=None,
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    session.add(run)
    await session.flush()
    job = WorkflowJob(run_id=run.id, job_type="report_planner", status="running")
    session.add(job)
    await session.flush()
    run.planner_job_id = job.id
    await session.commit()

    option = ReportPlanOption(
        id="pre-event-briefing",
        recommended=True,
        title="球队建设会前调研",
        summary="结合日程与公开阵容资料准备讨论",
        report_goal="准备球队建设讨论",
        template_id="pre_event_briefing",
        template_version="1.0.0",
        base_family="briefing_research",
        evidence_scope=EvidenceScope(
            references=[
                {"kind": "event", "id": event.id},
                {"kind": "contact", "id": contact.id},
            ]
        ),
        attention_questions=["两队当前阵容与建设策略有何差异？"],
        public_research_scope=PublicResearchBrief(
            entities=[
                ResearchEntity(
                    id="real-madrid",
                    kind="organization",
                    name="皇家马德里",
                ),
                ResearchEntity(
                    id="barcelona",
                    kind="organization",
                    name="巴塞罗那",
                ),
                ResearchEntity(
                    id="kevin",
                    kind="person",
                    name="Kevin",
                    qualifier="Eureka CEO",
                ),
            ],
            questions=["当前一线队阵容", "球队建设策略", "Kevin 的公开职业背景"],
        ),
        field_bindings={},
        web_search=CapabilityPolicy(policy="optional"),
        illustration=IllustrationPolicy(policy="none"),
        render_policy="report_html_v1",
    )
    provider = FakePlannerProvider(PlannerResult(options=[option]))

    assert await execute_report_planner_job(
        job,
        provider=provider,
        registry=TemplateRegistry.load(TEMPLATES),
        session_factory=AsyncSessionFactory,
    )

    assert provider.request.event.description.endswith("内部预算安排。")
    assert provider.request.event.attendees[0].contact_id == contact.id
    await session.refresh(run)
    assert run.plan_draft["evidence_scope"]["references"] == [
        {"kind": "event", "id": event.id},
        {"kind": "contact", "id": contact.id},
    ]
    assert [
        entity["name"]
        for entity in run.plan_draft["public_research_scope"]["entities"]
    ] == ["皇家马德里", "巴塞罗那", "Kevin"]
    assert "内部预算安排" not in str(run.plan_draft["public_research_scope"])


async def test_planner_tools_are_owner_scoped_and_bounded(session):
    own_skills = [_skill(user_id="user-1", name=f"Own {index}") for index in range(6)]
    other = _skill(user_id="user-2", name="Other")
    session.add_all([*own_skills, other])
    await session.flush()
    for skill in [*own_skills, other]:
        session.add_all(
            [_asset(user_id=skill.user_id, skill=skill, index=index) for index in range(5)]
        )
    await session.flush()

    tools = PlannerTools(
        session,
        user_id="user-1",
        limits=PlannerLimits(
            max_candidate_skills=5,
            max_summaries_per_skill=3,
            max_total_summaries=7,
            max_serialized_context_bytes=4096,
        ),
    )
    listed = await tools.list_user_skills()
    summaries = []
    for skill in listed:
        summaries.extend(await tools.get_asset_summaries(skill.id))

    assert len(listed) == 5
    assert all(skill.user_id == "user-1" for skill in listed)
    assert len(summaries) == 7
    assert all(item.user_skill_id != other.id for item in summaries)
    per_skill_tools = PlannerTools(
        session,
        user_id="user-1",
        limits=PlannerLimits(
            max_candidate_skills=5,
            max_summaries_per_skill=3,
            max_total_summaries=100,
            max_serialized_context_bytes=4096,
        ),
    )
    assert len(await per_skill_tools.get_asset_summaries(listed[0].id)) == 3
    assert await per_skill_tools.get_asset_summaries(listed[0].id) == []
    assert set(PlannerTools.PUBLIC_METHODS) == {
        "list_user_skills",
        "get_skill_schema",
        "query_assets",
        "get_asset_summaries",
        "get_event",
        "get_event_attendees",
        "get_event_files",
        "get_related_sessions",
    }


async def test_planner_uses_custom_skill_schema_and_persists_primary_option(session):
    primary = _skill(
        user_id="user-1",
        name="果果日常",
        capabilities=["time_series_measurement", "daily_log"],
    )
    related = _skill(
        user_id="user-1",
        name="吃饭小本",
        capabilities=["categorical_intake"],
    )
    session.add_all([primary, related])
    await session.flush()
    asset = _asset(user_id="user-1", skill=primary, index=1)
    session.add(asset)
    await session.flush()
    run = _run(user_id="user-1", skill=primary, asset=asset)
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_planner",
        status="running",
    )
    session.add(job)
    await session.flush()
    run.planner_job_id = job.id
    await session.commit()

    provider = FakePlannerProvider(
        PlannerResult(options=[_option(skill_ids=[primary.id], asset_ids=[asset.id])])
    )
    registry = TemplateRegistry.load(TEMPLATES)
    written = await execute_report_planner_job(
        job,
        provider=provider,
        registry=registry,
        session_factory=AsyncSessionFactory,
    )

    assert written is True
    assert provider.calls == 1
    assert provider.request.primary_skills[0].display_name == "果果日常"
    assert {item.id for item in provider.request.related_skills} == {related.id}
    assert "child_growth_review" in {
        item.id for item in provider.request.templates
    }
    await session.refresh(run)
    assert run.state == "awaiting_selection"
    assert run.pending_decision == {
        "type": "plan_selection",
        "questions": [],
        "recommended_option_id": "primary",
    }
    assert len(run.plan_options) == 1
    notifications = list(await session.scalars(select(Notification)))
    assert [(item.type, item.link) for item in notifications] == [
        ("report_plan_ready", f"report-run:{run.id}")
    ]
    assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1


async def test_planner_normalizes_current_flat_skill_schema(session):
    skill = _skill(user_id="user-1", name="舞蹈记录")
    skill.schema_json = {
        "duration_minutes": {
            "type": "number",
            "label": "时长",
            "required": False,
        },
        "venue": {
            "type": "string",
            "label": "地点",
            "required": False,
        },
        "x-routing-profile": {"intent": "记录已经发生的舞蹈活动"},
    }
    session.add(skill)
    await session.flush()
    asset = _asset(user_id="user-1", skill=skill, index=1)
    session.add(asset)
    await session.flush()
    run = _run(user_id="user-1", skill=skill, asset=asset)
    session.add(run)
    await session.flush()

    request = await build_planner_request(
        run=run,
        tools=PlannerTools(session, user_id="user-1"),
        registry=TemplateRegistry.load(TEMPLATES),
    )

    assert set(request.primary_skills[0].capabilities) >= {
        "daily_log",
        "free_text",
        "location",
        "time_series_measurement",
    }
    assert {template.id for template in request.templates} >= {
        "general_period_review",
        "idea_synthesis",
    }


async def test_planner_can_request_clarification_and_notification_is_deduplicated(
    session,
):
    skill = _skill(user_id="user-1", name="Sparse")
    session.add(skill)
    await session.flush()
    asset = _asset(user_id="user-1", skill=skill, index=1)
    session.add(asset)
    await session.flush()
    run = _run(user_id="user-1", skill=skill, asset=asset)
    session.add(run)
    await session.flush()
    job = WorkflowJob(run_id=run.id, job_type="report_planner", status="running")
    session.add(job)
    await session.flush()
    run.planner_job_id = job.id
    await session.commit()
    result = PlannerResult(
        clarification_questions=[
            ClarificationQuestion(
                id="goal",
                question="你想重点看什么？",
                options=["变化", "规律"],
            )
        ]
    )
    provider = FakePlannerProvider(result)
    registry = TemplateRegistry.load(TEMPLATES)

    assert await execute_report_planner_job(
        job,
        provider=provider,
        registry=registry,
        session_factory=AsyncSessionFactory,
    )
    async with AsyncSessionFactory() as write_session:
        # The same current result cannot create a second notification/outbox.
        assert await persist_planner_result(
            write_session,
            run_id=run.id,
            job_id=job.id,
            result=result,
        ) is False
        await write_session.commit()

    await session.refresh(run)
    assert run.state == "awaiting_selection"
    assert run.pending_decision["type"] == "clarification"
    assert await session.scalar(select(func.count()).select_from(Notification)) == 1
    assert await session.scalar(select(func.count()).select_from(OutboxEvent)) == 1


async def test_planner_exhaustion_marks_run_failed_instead_of_leaving_it_planning(
    session,
):
    skill = _skill(user_id="user-1", name="Failure")
    session.add(skill)
    await session.flush()
    asset = _asset(user_id="user-1", skill=skill, index=1)
    session.add(asset)
    await session.flush()
    run = _run(user_id="user-1", skill=skill, asset=asset)
    session.add(run)
    await session.flush()
    job = WorkflowJob(
        run_id=run.id,
        job_type="report_planner",
        status="running",
        attempt=3,
        max_attempts=3,
        lease_owner="worker-1",
    )
    session.add(job)
    await session.flush()
    run.planner_job_id = job.id
    await session.commit()

    with pytest.raises(RetryableProviderError):
        await execute_report_planner_job(
            job,
            provider=FailingPlannerProvider(),
            registry=TemplateRegistry.load(TEMPLATES),
            session_factory=AsyncSessionFactory,
        )

    await session.refresh(run)
    assert run.state == "failed"
    assert run.failure_stage == "planning"
    assert run.retry_from == "planning"
    assert run.error_message == "报告方案生成失败，请重试。"
    notifications = list(await session.scalars(select(Notification)))
    assert [(item.type, item.link) for item in notifications] == [
        ("report_failed", f"report-run:{run.id}")
    ]


async def test_planner_rejects_stale_write_and_non_primary_baseline(session):
    primary = _skill(user_id="user-1", name="Primary")
    related = _skill(user_id="user-1", name="Related")
    session.add_all([primary, related])
    await session.flush()
    asset = _asset(user_id="user-1", skill=primary, index=1)
    session.add(asset)
    await session.flush()
    run = _run(user_id="user-1", skill=primary, asset=asset)
    run.planner_job_id = "current-job"
    session.add(run)
    await session.flush()

    tools = PlannerTools(session, user_id="user-1")
    from app.domains.reports.planner import build_planner_request

    request = await build_planner_request(
        run=run,
        tools=tools,
        registry=TemplateRegistry.load(TEMPLATES),
    )
    combined_only = PlannerResult(
        options=[
            _option(
                skill_ids=[primary.id, related.id],
                asset_ids=[asset.id],
            )
        ]
    )

    with pytest.raises(InvalidPlannerResult, match="primary-only"):
        validate_planner_result(
            request=request,
            result=combined_only,
            registry=TemplateRegistry.load(TEMPLATES),
        )
    assert await persist_planner_result(
        session,
        run_id=run.id,
        job_id="stale-job",
        result=PlannerResult(
            clarification_questions=[
                ClarificationQuestion(id="goal", question="Goal?")
            ]
        ),
    ) is False
    assert run.state == "planning"


def test_planner_result_is_strict_and_has_three_option_maximum():
    option = _option(skill_ids=["skill-1"], asset_ids=["asset-1"])

    with pytest.raises(ValidationError):
        PlannerResult.model_validate(
            {"options": [option.model_dump()] * 4, "unexpected": True}
        )
