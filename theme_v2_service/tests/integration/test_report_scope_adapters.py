from datetime import datetime, timedelta, timezone

from app.db.models import Asset, Event, UserSkill
from app.domains.reports.scope_adapters import (
    infer_scope_adapter,
    initial_scope,
    list_scope_candidates,
)


NOW = datetime(2026, 8, 11, 12, 0, tzinfo=timezone.utc)


def test_report_scope_router_recognizes_categories_without_exact_sentence_matches():
    assert infer_scope_adapter("请准备明晚会议的会前背景") == "pre_event_briefing"
    assert infer_scope_adapter("复盘本周的喝水和跑步数据") == "period_summary"
    assert infer_scope_adapter("研究一下欧洲足球青训") == "generic"


def test_period_summary_initial_scope_resolves_the_local_week():
    draft = initial_scope(
        "帮我汇总一下这周我的几个记录的数据",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert draft.adapter_kind == "period_summary"
    assert draft.time_range is not None
    assert draft.time_range.from_at.isoformat() == "2026-08-10T00:00:00+08:00"
    assert draft.time_range.to_at.isoformat() == "2026-08-17T00:00:00+08:00"


async def test_pre_event_candidates_are_only_the_next_three_active_events(session):
    starts = [
        ("past", NOW - timedelta(minutes=30), "scheduled"),
        ("first", NOW + timedelta(minutes=30), "scheduled"),
        ("cancelled", NOW + timedelta(minutes=45), "cancelled"),
        ("second", NOW + timedelta(hours=1), "scheduled"),
        ("third", NOW + timedelta(hours=2), "scheduled"),
        ("fourth", NOW + timedelta(hours=3), "scheduled"),
    ]
    for event_id, start, status in starts:
        session.add(
            Event(
                id=event_id,
                user_id="user-1",
                title=event_id,
                description=f"{event_id} notes",
                start_at=start.replace(tzinfo=None),
                end_at=(start + timedelta(hours=1)).replace(tzinfo=None),
                all_day=False,
                status=status,
            )
        )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="pre_event_briefing",
        intent="会前调研",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [event.reference.id for event in response.events] == [
        "first",
        "second",
        "third",
    ]
    assert [event.local_start for event in response.events] == [
        "20:30",
        "21:00",
        "22:00",
    ]
    assert response.events[0].notes == "first notes"


async def test_period_summary_defaults_all_aggregatable_in_period_records(session):
    water = UserSkill(
        id="skill-water",
        user_id="user-1",
        machine_name="water_intake_log",
        display_name="喝水记录",
        schema_json={
            "type": "object",
            "properties": {"volume_ml": {"type": "number"}},
        },
    )
    running = UserSkill(
        id="skill-running",
        user_id="user-1",
        machine_name="running_log",
        display_name="跑步记录",
        schema_json={
            "type": "object",
            "properties": {"distance_km": {"type": "number"}},
        },
    )
    notes = UserSkill(
        id="skill-notes",
        user_id="user-1",
        machine_name="notes",
        display_name="随记",
        schema_json={
            "type": "object",
            "properties": {"content": {"type": "string"}},
        },
    )
    session.add_all([water, running, notes])
    await session.flush()
    session.add_all(
        [
            Asset(
                id="water-1",
                user_id="user-1",
                user_skill_id=water.id,
                payload_json={"volume_ml": 500},
                effective_at=datetime(2026, 8, 10, 1, 0),
            ),
            Asset(
                id="run-1",
                user_id="user-1",
                user_skill_id=running.id,
                payload_json={"distance_km": 5},
                effective_at=datetime(2026, 8, 11, 1, 0),
            ),
            Asset(
                id="note-1",
                user_id="user-1",
                user_skill_id=notes.id,
                payload_json={"content": "ordinary note"},
                effective_at=datetime(2026, 8, 11, 2, 0),
            ),
            Asset(
                id="water-old",
                user_id="user-1",
                user_skill_id=water.id,
                payload_json={"volume_ml": 250},
                effective_at=datetime(2026, 8, 8, 1, 0),
            ),
        ]
    )
    await session.commit()

    response = await list_scope_candidates(
        session,
        user_id="user-1",
        adapter_kind="period_summary",
        intent="汇总这周我的记录",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [group.skill_id for group in response.record_groups] == [
        "skill-running",
        "skill-water",
    ]
    assert all(group.default_selected for group in response.record_groups)
    assert {
        record.reference.id
        for group in response.record_groups
        for record in group.records
    } == {"water-1", "run-1"}
    assert response.default_scope.skill_ids == ["skill-running", "skill-water"]
    assert response.default_scope.additional_focus == ""
