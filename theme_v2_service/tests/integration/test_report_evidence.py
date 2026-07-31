from pathlib import Path

import pytest

from app.db.models import Asset, UserSkill
from app.domains.reports.evidence import InsufficientEvidence, load_latest_evidence
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import ReportExecutionPlan
from app.domains.reports.templates import TemplateRegistry


TEMPLATES = Path(__file__).parents[2] / "report-templates"


def _plan(asset_ids: list[str]) -> ReportExecutionPlan:
    return ReportExecutionPlan(
        template_id="general_period_review",
        template_version="1.0.0",
        base_family="theme_synthesis",
        report_goal="Summarize the period",
        resolved_asset_ids=asset_ids,
        field_bindings={
            "record.value": "payload.value",
            "record.when": "effective_at",
        },
        web_policy="none",
        illustration_policy="optional",
        render_policy="report_html_v1",
    )


async def _skill(session, *, user_id: str, name: str) -> UserSkill:
    skill = UserSkill(
        user_id=user_id,
        machine_name=name,
        display_name=name,
        description=None,
        domain="notes",
        schema_json={
            "type": "object",
            "x-data-capabilities": ["free_text"],
        },
    )
    session.add(skill)
    await session.flush()
    return skill


async def _asset(session, *, user_id: str, skill: UserSkill, value: str) -> Asset:
    asset = Asset(
        user_id=user_id,
        user_skill_id=skill.id,
        payload_json={"value": value},
    )
    session.add(asset)
    await session.flush()
    return asset


def _run(*, user_id: str) -> ReportGenerationRun:
    return ReportGenerationRun(
        user_id=user_id,
        origin="user_initiated",
        state="generating",
        active_stage="load_evidence",
        launch_context={},
        intent="summary",
        answers={},
        evidence_scope={},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )


async def test_evidence_uses_latest_owned_assets_in_requested_order(session):
    own_skill = await _skill(session, user_id="user-1", name="own")
    other_skill = await _skill(session, user_id="user-2", name="other")
    first = await _asset(session, user_id="user-1", skill=own_skill, value="old")
    second = await _asset(session, user_id="user-1", skill=own_skill, value="second")
    cross_user = await _asset(
        session,
        user_id="user-2",
        skill=other_skill,
        value="must-not-leak",
    )
    await session.commit()
    first.payload_json = {"value": "latest"}
    await session.commit()
    run = _run(user_id="user-1")

    bundle = await load_latest_evidence(
        session,
        run=run,
        execution_plan=_plan(
            [second.id, "deleted-id", cross_user.id, first.id]
        ),
        registry=TemplateRegistry.load(TEMPLATES),
    )

    assert [item.asset_id for item in bundle.user_evidence] == [second.id, first.id]
    assert bundle.user_evidence[1].payload == {"value": "latest"}
    assert bundle.user_evidence[1].bound_fields["record.value"] == "latest"
    assert bundle.unavailable_asset_ids == ["deleted-id", cross_user.id]
    assert "must-not-leak" not in bundle.model_dump_json()


async def test_sufficient_remainder_continues_when_one_asset_disappears(session):
    skill = await _skill(session, user_id="user-1", name="own")
    remaining = await _asset(session, user_id="user-1", skill=skill, value="kept")
    await session.commit()

    bundle = await load_latest_evidence(
        session,
        run=_run(user_id="user-1"),
        execution_plan=_plan(["missing", remaining.id]),
        registry=TemplateRegistry.load(TEMPLATES),
    )

    assert [item.asset_id for item in bundle.user_evidence] == [remaining.id]
    assert bundle.unavailable_asset_ids == ["missing"]


async def test_all_unavailable_fails_before_any_paid_provider(session):
    with pytest.raises(InsufficientEvidence, match="minimum data"):
        await load_latest_evidence(
            session,
            run=_run(user_id="user-1"),
            execution_plan=_plan(["missing", "cross-user-or-deleted"]),
            registry=TemplateRegistry.load(TEMPLATES),
        )
