import pytest
from pydantic import ValidationError

from app.domains.assets.service import ensure_capture_skills, list_user_skills
from app.domains.capture.agent import (
    CaptureAgentRequest,
    CaptureAgentResult,
    CaptureOutputError,
    CaptureRecordCommand,
    CaptureSkill,
    capture_skill_from_model,
    validate_capture_result,
)
from app.db.models import GlobalSkill, UserSkill


async def test_baseline_capture_skills_are_idempotent(session):
    session.add_all(
        [
            GlobalSkill(
                machine_name=name,
                display_name=name,
                entity_kind=(
                    name if name in {"contact", "event"} else "asset"
                ),
            )
            for name in ("todo", "expense", "contact", "notes", "event")
        ]
    )
    await session.flush()
    first = await ensure_capture_skills(session, "user-1")
    second = await ensure_capture_skills(session, "user-1")

    assert [skill.machine_name for skill in first] == [
        "todo",
        "expense",
        "contact",
        "notes",
        "event",
    ]
    assert [skill.id for skill in second] == [skill.id for skill in first]
    assert all(skill.schema_json["x-capture-enabled"] is True for skill in first)
    assert all(skill.global_skill_id is not None for skill in first)
    notes = next(skill for skill in first if skill.machine_name == "notes")
    assert "tags" not in notes.schema_json["properties"]
    assert notes.schema_json["required"] == ["title", "content"]


async def test_baseline_skills_backfill_localized_titles_without_overwriting_user_schema(
    session,
):
    existing = UserSkill(
        user_id="user-1",
        machine_name="todo",
        display_name="待办",
        schema_json={
            "type": "object",
            "properties": {
                "title": {"type": "string", "description": "user description"},
                "content": {"type": "string", "title": "我的内容"},
                "custom_field": {"type": "string", "title": "自定义"},
            },
            "required": ["title"],
            "additionalProperties": False,
            "x-capture-enabled": True,
        },
        render_spec_json={"icon": "⭐", "primary_field": "content"},
    )
    session.add(existing)
    await session.flush()

    skills = await ensure_capture_skills(session, "user-1")

    by_name = {skill.machine_name: skill for skill in skills}
    todo = by_name["todo"]
    assert set(todo.schema_json["properties"]) == {
        "title",
        "content",
        "custom_field",
    }
    assert todo.schema_json["properties"]["title"] == {
        "type": "string",
        "description": "user description",
        "title": "标题",
    }
    assert todo.schema_json["properties"]["content"]["title"] == "我的内容"
    assert todo.schema_json["properties"]["custom_field"]["title"] == "自定义"
    assert todo.render_spec_json == {"icon": "⭐", "primary_field": "content"}
    assert by_name["notes"].schema_json["properties"]["content"]["title"] == "内容"
    assert by_name["contact"].schema_json["properties"]["company"]["title"] == "公司"
    assert by_name["event"].schema_json["properties"]["start_at"]["title"] == "开始时间"


async def test_listing_skills_bootstraps_all_configurable_system_containers(session):
    session.add_all(
        [
            GlobalSkill(
                machine_name=name,
                display_name=name,
                entity_kind=(
                    name if name in {"contact", "event"} else "asset"
                ),
            )
            for name in ("todo", "expense", "contact", "notes", "event")
        ]
    )
    await session.flush()

    skills = await list_user_skills(session, "user-1")

    by_name = {skill.machine_name: skill for skill in skills}
    assert {"todo", "notes", "contact", "event"} <= by_name.keys()
    assert by_name["event"].global_skill_id is not None
    assert set(by_name["event"].schema_json["properties"]) == {
        "title",
        "start_at",
        "end_at",
        "location",
        "attendees",
        "description",
    }


def _skill(
    machine_name: str,
    *,
    enabled: bool = True,
    schema: dict | None = None,
) -> CaptureSkill:
    return CaptureSkill(
        machine_name=machine_name,
        display_name=machine_name,
        description=f"{machine_name} records",
        schema_definition=schema
        or {
            "type": "object",
            "properties": {"content": {"type": "string"}},
            "required": ["content"],
            "additionalProperties": False,
        },
        enabled=enabled,
    )


def test_event_and_expense_output_passes_dynamic_validation():
    result = CaptureAgentResult(
        summary="已记下项目会和咖啡消费。",
        records=[
            CaptureRecordCommand(
                kind="event",
                title="项目会",
                start_at="2026-08-03T15:00:00+08:00",
                end_at="2026-08-03T16:00:00+08:00",
                location="会议室 A",
                attendees=["冯总"],
            ),
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="expense",
                payload={
                    "amount": 28,
                    "currency": "CNY",
                    "category": "餐饮",
                },
                effective_at="2026-08-02T09:00:00+08:00",
            ),
        ],
    )
    expense = _skill(
        "expense",
        schema={
            "type": "object",
            "properties": {
                "amount": {"type": "number"},
                "currency": {"type": "string"},
                "category": {"type": "string"},
            },
            "required": ["amount", "currency"],
            "additionalProperties": False,
        },
    )

    assert validate_capture_result(result, [expense]) is result


def test_qa_output_can_return_summary_without_records():
    result = CaptureAgentResult(summary="长白山位于吉林省。", records=[])

    assert validate_capture_result(result, []) is result


@pytest.mark.parametrize(
    "skills",
    [
        [_skill("notes")],
        [_skill("running", enabled=False)],
    ],
)
def test_unknown_or_disabled_skill_is_rejected(skills):
    result = CaptureAgentResult(
        summary="已记录。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="running",
                payload={"content": "跑了五公里"},
            )
        ],
    )

    with pytest.raises(CaptureOutputError, match="unknown or disabled skill"):
        validate_capture_result(result, skills)


def test_invalid_event_range_is_rejected():
    with pytest.raises(ValidationError, match="end_at must be after start_at"):
        CaptureRecordCommand(
            kind="event",
            title="倒序会议",
            start_at="2026-08-03T16:00:00+08:00",
            end_at="2026-08-03T15:00:00+08:00",
        )


def test_enabled_custom_skill_accepts_matching_payload():
    running = _skill(
        "running",
        schema={
            "type": "object",
            "properties": {
                "distance_km": {"type": "number"},
                "duration_min": {"type": "integer"},
            },
            "required": ["distance_km"],
            "additionalProperties": False,
        },
    )
    result = CaptureAgentResult(
        summary="已记录跑步。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="running",
                payload={"distance_km": 5.2, "duration_min": 31},
            )
        ],
    )

    assert validate_capture_result(result, [running]) is result


def test_enabled_custom_skill_accepts_existing_shorthand_schema():
    model = UserSkill(
        id="skill-mood",
        user_id="user-1",
        machine_name="mood",
        display_name="心情",
        description="每日心情",
        domain="wellbeing",
        schema_json={
            "mood": {"type": "string"},
            "score": {"type": "integer"},
            "x-capture-enabled": True,
        },
    )
    skill = capture_skill_from_model(model)
    assert skill.user_skill_id == "skill-mood"
    result = CaptureAgentResult(
        summary="已记录心情。",
        records=[
            CaptureRecordCommand(
                kind="asset",
                skill_machine_name="mood",
                payload={"mood": "开心", "score": 8},
            )
        ],
    )

    assert validate_capture_result(result, [skill]) is result


def test_enabled_user_skill_is_capturable_without_schema_capability_marker():
    model = UserSkill(
        id="skill-water",
        user_id="user-1",
        machine_name="daily_water_intake",
        display_name="喝水记录",
        description="记录每次饮水量",
        schema_json={
            "type": "object",
            "properties": {
                "amount_ml": {"type": "number", "title": "饮水量"},
            },
        },
        enabled=True,
    )

    skill = capture_skill_from_model(model)

    assert skill.enabled is True
