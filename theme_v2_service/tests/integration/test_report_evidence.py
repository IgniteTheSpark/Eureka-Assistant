from datetime import datetime
from pathlib import Path

import pytest

from app.db.models import Asset, Contact, Event, EventAttendee, UserSkill
from app.domains.reports.evidence import InsufficientEvidence, load_latest_evidence
from app.domains.reports.models import ReportGenerationRun
from app.domains.reports.schemas import EvidenceReference, ReportExecutionPlan
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


async def test_evidence_resolves_fields_alias_and_builds_trusted_aggregates(session):
    skill = await _skill(session, user_id="user-1", name="expense")
    first = await _asset(session, user_id="user-1", skill=skill, value="unused")
    second = await _asset(session, user_id="user-1", skill=skill, value="unused")
    first.payload_json = {"amount": 8, "category": "餐饮"}
    second.payload_json = {"amount": 12, "category": "交通"}
    await session.commit()
    plan = _plan([first.id, second.id]).model_copy(
        update={
            "field_bindings": {
                "amount": "fields.amount",
                "category": "fields.category",
            }
        }
    )

    bundle = await load_latest_evidence(
        session,
        run=_run(user_id="user-1"),
        execution_plan=plan,
        registry=TemplateRegistry.load(TEMPLATES),
    )

    assert [item.bound_fields["amount"] for item in bundle.user_evidence] == [
        8,
        12,
    ]
    assert bundle.derived_metrics["record_count"] == 2
    assert bundle.derived_metrics["fields"]["amount"]["sum"] == 20
    assert bundle.derived_metrics["fields"]["category"]["distinct_count"] == 2
    assert bundle.derived_metrics["fields"]["category"]["counts_by_value"] == {
        "餐饮": 1,
        "交通": 1,
    }


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


async def test_evidence_loads_owned_event_contact_and_complete_private_fields(session):
    contact = Contact(
        user_id="user-1",
        name="Kevin",
        company="Eureka",
        title="CEO",
        notes_json=["内部联系人备注"],
        socials_json={"linkedin": "kevin-eureka"},
    )
    event = Event(
        user_id="user-1",
        title="球队建设情况讨论",
        description="比较皇家马德里和巴塞罗那，内部预算暂不公开。",
        location="会议室",
        start_at=datetime(2026, 8, 8, 15, 0),
        end_at=datetime(2026, 8, 8, 16, 0),
        all_day=False,
    )
    other_contact = Contact(
        user_id="user-2",
        name="Other",
        notes_json=[],
        socials_json={},
    )
    session.add_all([contact, event, other_contact])
    await session.flush()
    session.add(
        EventAttendee(
            event_id=event.id,
            contact_id=contact.id,
            name_raw="Kevin",
            role="attendee",
        )
    )
    await session.commit()
    plan = _plan([]).model_copy(
        update={
            "resolved_references": [
                EvidenceReference(kind="event", id=event.id),
                EvidenceReference(kind="contact", id=contact.id),
                EvidenceReference(kind="contact", id=other_contact.id),
            ]
        }
    )

    bundle = await load_latest_evidence(
        session,
        run=_run(user_id="user-1"),
        execution_plan=plan,
        registry=TemplateRegistry.load(TEMPLATES),
        timezone_name="Asia/Shanghai",
    )

    assert [(item.kind, item.reference_id) for item in bundle.user_evidence] == [
        ("event", event.id),
        ("contact", contact.id),
    ]
    assert bundle.user_evidence[0].payload["description"].endswith("暂不公开。")
    assert bundle.user_evidence[0].payload["attendees"][0]["name"] == "Kevin"
    assert bundle.user_evidence[0].effective_at.isoformat() == (
        "2026-08-08T23:00:00+08:00"
    )
    assert bundle.user_evidence[0].payload["start_at"].isoformat() == (
        "2026-08-08T23:00:00+08:00"
    )
    assert bundle.user_evidence[0].temporal_facts.model_dump() == {
        "timezone": "Asia/Shanghai",
        "local_date": "2026-08-08",
        "local_start_time": "23:00",
        "local_end_time": "00:00",
        "local_interval_text": "23:00–00:00",
        "duration_minutes": 60,
    }
    assert bundle.user_evidence[1].payload["notes"] == ["内部联系人备注"]
    assert bundle.unavailable_references == [
        {"kind": "contact", "id": other_contact.id}
    ]
