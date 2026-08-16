from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from sqlalchemy import func, select

from app.db.models import Asset, Event, UserSkill
from app.domains.notifications.models import Notification
from app.domains.reka.models import Nudge, RhythmProfile
from app.domains.reports.models import Report, ReportGenerationRun
from app.domains.reka.service import dismiss_signal, list_signals, snooze_signal
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
    rhythm = next(row for row in first["signals"] if row["kind"] == "rhythm_gap")
    assert rhythm["evidence"] == {
        "cadence": "daily",
        "period": "上午",
        "weekdays": [],
        "sample_n": 9,
        "pattern_key": "daily:上午",
        "cycle_key": "2026-08-10",
    }
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
    assert signal["natural_key"] == f"report:{execution.id}:opportunity"
    assert signal["phase"] == "opportunity"
    assert signal["chain_id"] == execution.id
    assert signal["report_run_id"] is None
    assert signal["report_id"] is None
    assert signal["target"] == {
        "type": "trigger_execution",
        "id": execution.id,
    }
    assert signal["actions"] == ["open", "dismiss"]


async def test_report_chain_surfaces_only_actionable_phase_and_supersedes_prior_nudge(
    session,
):
    event = Event(
        id="event-chain",
        user_id="user-1",
        title="产品路线会议",
        start_at=(NOW + timedelta(hours=2)).replace(tzinfo=None),
        end_at=(NOW + timedelta(hours=3)).replace(tzinfo=None),
        all_day=False,
    )
    execution = TriggerExecution(
        id="execution-chain",
        user_id="user-1",
        trigger_type="pre_event_report",
        workflow_type="report_generation",
        tracker_id=None,
        scope_type="event",
        scope_id=event.id,
        status="available",
        dedupe_key="pre-event:event-chain",
        revision=1,
        payload_json={"event_id": event.id, "event_title": event.title},
        first_fired_at=NOW.replace(tzinfo=None),
        last_fired_at=NOW.replace(tzinfo=None),
        expires_at=(NOW + timedelta(hours=2)).replace(tzinfo=None),
    )
    session.add_all([event, execution])
    await session.flush()
    opportunity = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    opportunity_id = opportunity["signals"][0]["id"]

    run = ReportGenerationRun(
        id="run-chain",
        user_id="user-1",
        origin="trigger",
        trigger_execution_id=execution.id,
        state="planning",
        launch_context=execution.payload_json,
        answers={},
        evidence_scope={"asset_ids": ["asset-1", "asset-2"]},
        plan_options=[],
        resolved_asset_ids=[],
        generation_context={},
        usage_json={},
    )
    execution.status = "consumed"
    execution.workflow_run_id = run.id
    session.add(run)
    await session.flush()
    planning = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=1),
        timezone_name="Asia/Shanghai",
    )
    opportunity_nudge = await session.get(Nudge, opportunity_id)

    assert planning["signals"] == []
    assert opportunity_nudge is not None
    assert opportunity_nudge.status == "expired"

    run.state = "awaiting_selection"
    run.pending_decision = {"type": "plan_selection", "recommended_option_id": "p1"}
    run.plan_options = [{"id": "p1", "title": "市场与竞品方案"}]
    run.plan_draft = {
        "selected_option_id": "p1",
        "attention_questions": ["核心差异是什么？"],
        "evidence_scope": {"asset_ids": ["asset-1", "asset-2"]},
    }
    run.plan_revision = 2
    await session.flush()
    plan_ready = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=2),
        timezone_name="Asia/Shanghai",
    )
    plan_signal = plan_ready["signals"][0]

    assert plan_signal["natural_key"] == "report:execution-chain:plan_ready"
    assert plan_signal["phase"] == "plan_ready"
    assert plan_signal["target"] == {"type": "report_run", "id": run.id}
    assert plan_signal["report_run_id"] == run.id
    assert plan_signal["report_id"] is None
    assert plan_signal["evidence"]["asset_count"] == 2

    run.plan_revision = 3
    await session.flush()
    revised = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=3),
        timezone_name="Asia/Shanghai",
    )
    assert revised["signals"][0]["id"] == plan_signal["id"]

    run.state = "generating"
    await session.flush()
    generating = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=4),
        timezone_name="Asia/Shanghai",
    )
    plan_nudge = await session.get(Nudge, plan_signal["id"])

    assert generating["signals"] == []
    assert plan_nudge is not None
    assert plan_nudge.status == "expired"

    report = Report(
        id="report-chain",
        user_id="user-1",
        generation_run_id=run.id,
        title="产品路线研究",
        template_id="brief",
        template_version="1",
        base_family="brief",
        content_md="## 结论\n优先聚焦核心工作流。",
        html=None,
        spec_json={},
        share_card_spec={},
        tokens_used=100,
        gen_ms=500,
    )
    session.add(report)
    run.state = "completed"
    run.report_id = report.id
    run.completed_at = (NOW + timedelta(minutes=5)).replace(tzinfo=None)
    await session.flush()
    report_ready = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=5),
        timezone_name="Asia/Shanghai",
    )
    ready_signal = report_ready["signals"][0]

    assert ready_signal["natural_key"] == "report:execution-chain:report_ready"
    assert ready_signal["phase"] == "report_ready"
    assert ready_signal["target"] == {"type": "report", "id": report.id}
    assert ready_signal["report_run_id"] == run.id
    assert ready_signal["report_id"] == report.id
    assert ready_signal["evidence"]["summary"].startswith("结论")


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


async def test_snoozed_occurrence_reappears_then_due_change_expires_it(session):
    todo = await _overdue_todo(session)
    first = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    signal_id = first["signals"][0]["id"]

    await snooze_signal(
        session,
        user_id="user-1",
        signal_id=signal_id,
        remind_again_at=NOW + timedelta(hours=1),
        now=NOW,
    )
    hidden = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(minutes=30),
        timezone_name="Asia/Shanghai",
    )
    resurfaced = await list_signals(
        session,
        user_id="user-1",
        now=NOW + timedelta(hours=1),
        timezone_name="Asia/Shanghai",
    )

    assert hidden["signals"] == []
    assert resurfaced["signals"][0]["id"] == signal_id

    todo.payload_json = {
        **todo.payload_json,
        "due_date": "2026-08-10T01:30:00Z",
    }
    await session.flush()
    replaced = await list_signals(
        session,
        user_id="user-1",
        now=NOW,
        timezone_name="Asia/Shanghai",
    )
    old = await session.get(Nudge, signal_id)

    assert replaced["signals"][0]["natural_key"].endswith(
        "2026-08-10T01:30:00Z"
    )
    assert replaced["signals"][0]["id"] != signal_id
    assert old is not None
    assert old.status == "expired"
    assert old.remind_again_at is None


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
