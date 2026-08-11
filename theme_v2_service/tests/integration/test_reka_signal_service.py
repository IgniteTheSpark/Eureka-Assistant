from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from app.db.models import Asset, Event, UserSkill
from app.domains.notifications.models import Notification
from app.domains.reka.models import Nudge, RhythmProfile
from app.domains.reka.service import dismiss_signal, list_signals
from app.domains.triggers.models import TriggerExecution


UTC = timezone.utc
SHANGHAI = ZoneInfo("Asia/Shanghai")
NOW = datetime(2026, 8, 10, 2, 0, tzinfo=UTC)


def _db(local_day: int, hour: int) -> datetime:
    return datetime(
        2026,
        8,
        local_day,
        hour,
        tzinfo=SHANGHAI,
    ).astimezone(UTC).replace(tzinfo=None)


async def _skill(session, machine: str, display: str) -> UserSkill:
    skill = UserSkill(
        id=f"skill-{machine}",
        user_id="user-1",
        machine_name=machine,
        display_name=display,
        schema_json={},
        render_spec_json={},
    )
    session.add(skill)
    await session.flush()
    return skill


async def _overdue_todo(session) -> Asset:
    todo = await _skill(session, "todo", "待办")
    asset = Asset(
        id="todo-1",
        user_id="user-1",
        user_skill_id=todo.id,
        payload_json={
            "title": "提交方案",
            "due_date": "2026-08-10T01:00:00Z",
            "status": "pending",
        },
    )
    session.add(asset)
    await session.flush()
    return asset


async def _rhythm_gap(session) -> None:
    breakfast = await _skill(session, "breakfast", "早餐记录")
    for day in range(1, 10):
        session.add(
            Asset(
                id=f"breakfast-{day}",
                user_id="user-1",
                user_skill_id=breakfast.id,
                payload_json={"meal": "早餐"},
                created_at=_db(day, 8),
                updated_at=_db(day, 8),
            )
        )
    session.add(
        RhythmProfile(
            user_id="user-1",
            skill="breakfast",
            timezone_name="Asia/Shanghai",
            patterns_json=[
                {
                    "pattern_key": "daily:上午",
                    "cadence": "daily",
                    "period": "上午",
                    "weekdays": [],
                    "confidence": 0.8,
                    "sample_n": 9,
                }
            ],
            computed_at=_db(10, 0),
        )
    )
    await session.flush()


async def test_read_is_idempotent_ranked_and_does_not_create_notifications(session):
    await _overdue_todo(session)
    await _rhythm_gap(session)

    first = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    second = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [row["kind"] for row in first["signals"]] == [
        "rhythm_gap",
        "overdue",
    ]
    assert [row["id"] for row in second["signals"]] == [
        row["id"] for row in first["signals"]
    ]
    assert await session.scalar(select(func.count()).select_from(Nudge)) == 2
    assert await session.scalar(select(func.count()).select_from(Notification)) == 0


async def test_available_pre_event_execution_is_a_reka_report_signal(session):
    event = Event(
        id="event-report",
        user_id="user-1",
        title="球队建设会议",
        description="对比欧美足球体系",
        start_at=(NOW + timedelta(hours=2)).replace(tzinfo=None),
        end_at=(NOW + timedelta(hours=3)).replace(tzinfo=None),
        all_day=False,
    )
    execution = TriggerExecution(
        id="execution-report",
        user_id="user-1",
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        tracker_id=None,
        scope_type="event",
        scope_id=event.id,
        status="available",
        dedupe_key="pre-event:event-report",
        revision=1,
        payload_json={
            "event_id": event.id,
            "event_title": event.title,
        },
        first_fired_at=NOW.replace(tzinfo=None),
        last_fired_at=NOW.replace(tzinfo=None),
        expires_at=(NOW + timedelta(hours=2)).replace(tzinfo=None),
    )
    session.add_all([event, execution])
    await session.flush()

    result = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    signal = result["signals"][0]
    assert signal["kind"] == "report"
    assert signal["natural_key"] == f"report:{execution.id}"
    assert signal["target"] == {
        "type": "trigger_execution",
        "id": execution.id,
    }
    assert signal["actions"] == ["open", "dismiss"]


async def test_report_signal_ignores_stale_cancelled_and_cross_user_events(session):
    cases = [
        ("past", "user-1", NOW - timedelta(hours=1), "scheduled"),
        ("cancelled", "user-1", NOW + timedelta(hours=1), "cancelled"),
        ("other", "user-2", NOW + timedelta(hours=1), "scheduled"),
    ]
    for name, user_id, start_at, status in cases:
        event = Event(
            id=f"event-{name}",
            user_id=user_id,
            title=name,
            start_at=start_at.replace(tzinfo=None),
            end_at=(start_at + timedelta(hours=1)).replace(tzinfo=None),
            all_day=False,
            status=status,
        )
        session.add(event)
        session.add(
            TriggerExecution(
                id=f"execution-{name}",
                user_id=user_id,
                trigger_type="pre_event_report",
                workflow_type="report_generation",
                tracker_id=None,
                scope_type="event",
                scope_id=event.id,
                status="available",
                dedupe_key=f"pre-event:{name}",
                revision=1,
                payload_json={"event_id": event.id, "event_title": name},
                first_fired_at=NOW.replace(tzinfo=None),
                last_fired_at=NOW.replace(tzinfo=None),
                expires_at=(NOW + timedelta(hours=2)).replace(tzinfo=None),
            )
        )
    await session.flush()

    result = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert result["signals"] == []


async def test_dismissed_overdue_occurrence_stays_hidden_but_reschedule_is_new(session):
    todo = await _overdue_todo(session)
    first = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    signal_id = first["signals"][0]["id"]

    dismissed = await dismiss_signal(
        session,
        user_id="user-1",
        signal_id=signal_id,
        now=NOW,
    )
    repeated = await dismiss_signal(
        session,
        user_id="user-1",
        signal_id=signal_id,
        now=NOW,
    )
    hidden = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    todo.payload_json = {
        **todo.payload_json,
        "due_date": "2026-08-10T01:30:00Z",
    }
    await session.flush()
    rescheduled = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert dismissed.status == repeated.status == "dismissed"
    assert hidden["signals"] == []
    assert rescheduled["signals"][0]["natural_key"].endswith(
        "2026-08-10T01:30:00Z"
    )
    assert rescheduled["signals"][0]["id"] != signal_id


async def test_source_failure_does_not_hide_healthy_candidates(
    session,
    monkeypatch,
):
    await _overdue_todo(session)

    async def fail_rhythm(*args, **kwargs):
        del args, kwargs
        raise RuntimeError("profile unavailable")

    monkeypatch.setattr(
        "app.domains.reka.service.collect_rhythm_candidates",
        fail_rhythm,
    )

    result = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )

    assert [row["kind"] for row in result["signals"]] == ["overdue"]
    assert result["partial_failures"] == ["rhythm"]
